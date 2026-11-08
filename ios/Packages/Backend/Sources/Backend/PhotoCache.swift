import Foundation

/// Check-in photos kept on the phone, so a photo seen once in 动态 or 我的动态 isn't downloaded
/// again. Kept by the photo's path in storage, never its view URL, which the API signs afresh on
/// every list; a path names one upload, which one check-in uses and never changes.
///
/// At most `limit` bytes: past it, the photos of the posts posted longest ago go until a fifth is
/// free. Not the ones seen longest ago: 动态 always opens on the latest posts, so scrolling far
/// back once would otherwise push out the photos the next open needs first. It lives in the
/// system's Caches folder, which iOS may empty when the phone runs short and never backs up.
public actor PhotoCache {
    /// 50 MB: some 150 photos at the size the app uploads.
    public static let defaultLimit = 50 * 1024 * 1024

    private let directory: URL
    private let limit: Int
    /// The bytes on disk, once counted; nil until the first write needs them.
    private var total: Int?
    /// Counts the clears: a download that started before the last one isn't kept.
    public private(set) var generation = 0

    /// - Parameters:
    ///   - directory: where the photos go, such as a folder in Caches; made when first needed.
    ///   - limit: the most bytes kept.
    public init(directory: URL, limit: Int = PhotoCache.defaultLimit) {
        self.directory = directory
        self.limit = limit
    }

    /// The photo at `path` when it is kept.
    public func photo(at path: String) -> Data? {
        try? Data(contentsOf: file(for: path))
    }

    /// Keeps the photo at `path` of a post posted at `postedAt`, then makes room when the cache is
    /// over its limit, which may drop this photo itself when every other is of a later post.
    /// Given the `generation` its download started in, it keeps nothing once the cache was cleared
    /// since, so a photo still on its way at sign-out isn't kept for the next account.
    public func keep(_ data: Data, at path: String, postedAt: Date, startedIn generation: Int? = nil) {
        let file = file(for: path)
        guard generation.map({ $0 == self.generation }) ?? true, data.count <= limit,
            !FileManager.default.fileExists(atPath: file.path())
        else { return }
        let total = self.total ?? counted()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        // The file's date is its post's, which is what the cache orders by.
        try? FileManager.default.setAttributes([.modificationDate: postedAt], ofItemAtPath: file.path())
        self.total = total + data.count > limit ? trimmed(to: limit * 4 / 5) : total + data.count
    }

    /// Deletes every photo, when the member signs out or deletes their account.
    public func forgetAll() {
        try? FileManager.default.removeItem(at: directory)
        total = 0
        generation += 1
    }

    /// A path such as `<uuid>/<uuid>` as one file name.
    private func file(for path: String) -> URL {
        directory.appending(path: path.replacingOccurrences(of: "/", with: "_"), directoryHint: .notDirectory)
    }

    private func kept() -> [(file: URL, size: Int, postedAt: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files =
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files.compactMap { file in
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
            return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }

    private func counted() -> Int { kept().reduce(0) { $0 + $1.size } }

    /// Keeps the photos of the latest posts up to `bytes`, deletes the rest, and returns what is
    /// kept.
    private func trimmed(to bytes: Int) -> Int {
        var total = 0
        var full = false
        for photo in kept().sorted(by: { $0.postedAt > $1.postedAt }) {
            full = full || total + photo.size > bytes
            if full {
                try? FileManager.default.removeItem(at: photo.file)
            } else {
                total += photo.size
            }
        }
        return total
    }
}
