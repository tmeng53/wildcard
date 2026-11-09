import CheckInDomain
import Contracts
import Foundation
import HealthDomain

/// Posts a new workout from its reminder's long-press card over our API, without the app open:
/// the adapter behind `HealthDomain`'s `QuickPosting`. The post is kept in `QuickPostHandoff`
/// first, by its id, and left there when it can't go out, so the app sends it when it next opens;
/// sending it twice saves it once.
public struct APIQuickPoster: QuickPosting {
    private let api: WildcardAPI
    private let handoff: QuickPostHandoff
    private let now: @Sendable () -> Date
    private let newID: @Sendable () -> UUID

    public init(
        api: WildcardAPI, handoff: QuickPostHandoff, now: @escaping @Sendable () -> Date = { Date() },
        newID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.api = api
        self.handoff = handoff
        self.now = now
        self.newID = newID
    }

    public func post(_ post: QuickPost, struck: Set<WorkoutCell>, caption: String) async -> QuickPostOutcome {
        guard
            let pending = Self.pending(
                post, struck: struck, caption: caption, id: CheckInID(newID()), at: Timestamp(now()))
        else {
            return .refused
        }
        await handoff.keep(pending)
        do {
            guard let checkIn = try pending.checkIn() else { return .refused }
            _ = try await api.save(checkIn)
            await handoff.drop(pending.id)
            return .posted
        } catch let error as APIError {
            switch CheckInError(error) {
            case .notSent, .signedOut: return .waiting
            default:
                await handoff.drop(pending.id)
                return .refused
            }
        } catch {
            await handoff.drop(pending.id)
            return .refused
        }
    }

    /// The check-in the card posts: a 训练 of the workout's sport and minutes (none once 时长 is
    /// struck), shared to the squad, with no photos and the line typed, if any. Nil for a
    /// workout of no listed sport, which is posted from the compose page.
    static func pending(
        _ post: QuickPost, struck: Set<WorkoutCell>, caption: String = "", id: CheckInID, at time: Timestamp
    ) -> PendingCheckIn? {
        guard let activity = post.activity, let audience = try? Audience([post.squad]) else { return nil }
        let body = PostBody(photos: [], caption: caption, workout: post.posting(struck: struck))
        return PendingCheckIn(
            id: id, member: post.member, day: post.day, createdAt: time, audience: audience,
            draft: .trained(activity, struck.contains(.duration) ? nil : post.imported.minutes, body))
    }
}

/// Posts made from a reminder's card that haven't reached the server yet, kept in the app group
/// so the app adds them to its own outbox (`TodayStore.adopt`) when it next opens.
public actor QuickPostHandoff {
    private let outbox: DeviceOutbox

    /// - Parameter directory: the app group's container (`AppGroup.directory`), or a test's own.
    public init(directory: URL) {
        outbox = DeviceOutbox(directory: directory.appending(path: "quick-posts", directoryHint: .isDirectory))
    }

    func keep(_ post: PendingCheckIn) async {
        let kept = await outbox.load()
        await outbox.save(kept.filter { $0.id != post.id } + [post])
    }

    func drop(_ id: CheckInID) async {
        let kept = await outbox.load()
        guard kept.contains(where: { $0.id == id }) else { return }
        await outbox.save(kept.filter { $0.id != id })
    }

    /// Every post waiting, and none left here: the app's outbox has them from now on.
    public func takeAll() async -> [PendingCheckIn] {
        let kept = await outbox.load()
        if !kept.isEmpty { await outbox.save([]) }
        return kept
    }
}
