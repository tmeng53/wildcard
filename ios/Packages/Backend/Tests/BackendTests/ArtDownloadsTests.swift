import AvatarArt
import Contracts
import Foundation
import Synchronization
import Testing

@testable import Backend

// The art on the phone, downloaded from a stand-in bucket into a folder of its own.

private let svg = Data(
    ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 320"><circle cx="9" cy="9" r="4" fill="#1F2128"/></svg>"##
        .utf8)
private let json = Data(##"{"version":1,"base":"#2D5BA0","shades":["#28467E"]}"##.utf8)
/// A stand-in for SHA-256 on Linux: the bytes in hex, so each file has its own name.
private let hex: @Sendable (Data) -> String = { $0.map { String(format: "%02x", $0) }.joined() }
private let base = URL(string: "https://storage.test/art/")

/// A bucket holding `files`, counting what is downloaded.
private final class Bucket: Sendable {
    let files: [String: Data]
    let downloads = Mutex<[String]>([])

    init(_ files: [Data]) {
        self.files = Dictionary(
            uniqueKeysWithValues: files.flatMap { data in
                ["svg", "json", "png"].map { ("\(hex(data)).\($0)", data) }
            })
    }

    func fetch(_ url: URL) throws -> Data {
        downloads.withLock { $0.append(url.lastPathComponent) }
        guard let data = files[url.lastPathComponent] else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

private func file(_ path: String, _ data: Data, rig: Int = 1) -> ArtManifest.File {
    ArtManifest.File(path: path, sha256: hex(data), size: data.count, rigVersion: rig)
}

private func downloads(from bucket: Bucket, root: URL? = nil, build: String = "1") -> (ArtDownloads, URL) {
    let root = root ?? FileManager.default.temporaryDirectory.appending(path: "wildcard-art-\(UUID().uuidString)")
    return (ArtDownloads(root: root, fetch: { try bucket.fetch($0) }, digest: hex, build: build), root)
}

private func text(_ root: URL, _ path: String) -> String? {
    try? String(contentsOf: root.appending(path: "current").appending(path: path), encoding: .utf8)
}

@Test func aGenerationLandsWholeAndEachFileDownloadsOnce() async {
    let bucket = Bucket([svg, json])
    let (art, root) = downloads(from: bucket)
    let first = ArtManifest(
        generation: 3, baseURL: base,
        files: [file("avatar/art/hat/beanie/crown.svg", svg), file("avatar/art/hat/beanie/tones.json", json)])

    #expect(await art.update(to: first))
    #expect(text(root, "avatar/art/hat/beanie/tones.json") == ##"{"version":1,"base":"#2D5BA0","shades":["#28467E"]}"##)
    #expect(await !art.update(to: first))

    // The next generation keeps the hat and takes its colors back to the bundled file.
    let second = ArtManifest(generation: 4, baseURL: base, files: [file("avatar/art/hat/beanie/crown.svg", svg)])
    #expect(await art.update(to: second))
    #expect(text(root, "avatar/art/hat/beanie/crown.svg") != nil)
    #expect(text(root, "avatar/art/hat/beanie/tones.json") == nil)
    #expect(bucket.downloads.withLock { $0 } == ["\(hex(svg)).svg", "\(hex(json)).json"])
}

@Test func aFileNotDownloadedWholeKeepsTheArtThatWasThere() async {
    let bucket = Bucket([svg])
    let (art, root) = downloads(from: bucket)
    #expect(await art.update(to: ArtManifest(generation: 1, baseURL: base, files: [file("avatar/a/b.svg", svg)])))

    let wrongSize = ArtManifest.File(path: "avatar/a/c.svg", sha256: hex(svg), size: 3, rigVersion: 1)
    #expect(await !art.update(to: ArtManifest(generation: 2, baseURL: base, files: [wrongSize])))
    let absent = Data("<svg/>".utf8)
    #expect(await !art.update(to: ArtManifest(generation: 2, baseURL: base, files: [file("avatar/a/d.svg", absent)])))
    #expect(text(root, "avatar/a/b.svg") != nil)
}

@Test func aFileThisBuildCantReadIsLeftOutAndTheRestLands() async {
    let broken = Data(#"<svg viewBox="0 0 1 1"><text>hi</text></svg>"#.utf8)
    let notARig = Data(#"{"version":1}"#.utf8)
    let (art, root) = downloads(from: Bucket([svg, broken, notARig]))
    let files = [
        file("avatar/a/b.svg", svg), file("avatar/a/d.svg", broken), file("avatar/rig.json", notARig),
        file("avatar/moves/ski.json", notARig),
    ]
    #expect(await art.update(to: ArtManifest(generation: 1, baseURL: base, files: files)))
    #expect(text(root, "avatar/a/b.svg") != nil)
    #expect(text(root, "avatar/a/d.svg") == nil)
    #expect(text(root, "avatar/rig.json") == nil)
    #expect(text(root, "avatar/moves/ski.json") == nil)
}

@Test func aPieceWithAPartThisBuildCantReadIsLeftOutWhole() async {
    let broken = Data(#"<svg viewBox="0 0 1 1"><circle cx="1"/></svg>"#.utf8)
    let (art, root) = downloads(from: Bucket([svg, json, broken]))
    let files = [
        file("avatar/art/hat/zzcap/crown.svg", broken), file("avatar/art/hat/zzcap/tones.json", json),
        file("avatar/art/hat/beanie/crown.svg", svg),
    ]
    #expect(await art.update(to: ArtManifest(generation: 1, baseURL: base, files: files)))
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "current/avatar/art/hat/zzcap").path))
    #expect(text(root, "avatar/art/hat/beanie/crown.svg") != nil)
}

@Test func artForANewerRigOrOutsideTheTreeIsLeftOut() async {
    let (art, root) = downloads(from: Bucket([svg]))
    let files = [
        file("avatar/art/top/elbows/armL.svg", svg, rig: ArtTree.rigVersion + 1),
        file("avatar/../../Library/x.svg", svg),
        file("coaches/maotou/art/base/head.svg", svg),
    ]
    #expect(await art.update(to: ArtManifest(generation: 1, baseURL: base, files: files)))
    #expect(text(root, "avatar/art/top/elbows/armL.svg") == nil)
    #expect(text(root, "coaches/maotou/art/base/head.svg") != nil)
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Library").path(percentEncoded: false)))
}

@Test func updatesAtOnceDownloadOnceAndNeverGoBack() async {
    let bucket = Bucket([svg, json])
    let (art, root) = downloads(from: bucket)
    let newer = ArtManifest(generation: 5, baseURL: base, files: [file("avatar/art/hat/beanie/crown.svg", svg)])
    // Launch and a return to the app ask at once: one brings the tree, the other finds it current.
    async let launch = art.update(to: newer)
    async let back = art.update(to: newer)
    let changed = await [launch, back].filter { $0 }.count
    #expect(changed == 1)
    #expect(bucket.downloads.withLock { $0 } == ["\(hex(svg)).svg"])
    // A list older than the tree, read before the newer one, changes nothing.
    let older = ArtManifest(generation: 4, baseURL: base, files: [file("avatar/art/hat/beanie/tones.json", json)])
    #expect(await !art.update(to: older))
    #expect(text(root, "avatar/art/hat/beanie/crown.svg") != nil)
}

@Test func aNewBuildBringsTheSameGenerationAgain() async {
    let bucket = Bucket([svg])
    let (art, root) = downloads(from: bucket)
    let manifest = ArtManifest(generation: 2, baseURL: base, files: [file("avatar/a/b.svg", svg)])
    #expect(await art.update(to: manifest))
    #expect(await !art.update(to: manifest))
    // After an app update, what this build left out is tried again; kept files aren't downloaded.
    let (updated, _) = downloads(from: bucket, root: root, build: "2")
    #expect(await updated.update(to: manifest))
    #expect(bucket.downloads.withLock { $0 } == ["\(hex(svg)).svg"])
}
