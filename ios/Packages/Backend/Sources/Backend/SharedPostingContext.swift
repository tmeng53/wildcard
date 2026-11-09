import CheckInDomain
import Contracts
import Foundation
import HealthDomain

/// Who this phone posts for and where (`HealthDomain`'s `PostingContext`), kept in the app group
/// so a new workout's reminder, worked out in the background, and its long-press card can post
/// without the app open. The app writes it whenever the home loads; it is the member's, so it
/// goes when they sign out or leave the squad.
public struct SharedPostingContext: Sendable {
    private let file: URL

    /// - Parameter directory: the app group's container (`AppGroup.directory`), or a test's own.
    public init(directory: URL) {
        file = directory.appending(path: "posting.json")
    }

    public func save(_ home: Home) {
        let posted = home.checkIns.compactMap { checkIn -> WorkoutSource? in
            guard checkIn.member == home.member, case .trained(let training) = checkIn.entry else { return nil }
            return training.workout?.source
        }
        let context = PostingContext(
            member: home.member, squad: home.squad.id, squadName: home.squad.name,
            timeZone: home.timeZone.identifier, posted: Set(posted))
        guard let data = try? JSONEncoder().encode(context) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: file, options: .atomic)
        #endif
    }

    /// As the home last loaded; nil before it first did, and after `forget`.
    public func load() -> PostingContext? {
        guard let data = try? Data(contentsOf: file),
            let context = try? JSONDecoder().decode(PostingContext.self, from: data),
            context.version == 1
        else { return nil }
        return context
    }

    public func forget() {
        try? FileManager.default.removeItem(at: file)
    }
}
