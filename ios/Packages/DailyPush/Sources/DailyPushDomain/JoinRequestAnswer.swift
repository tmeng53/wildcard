import Foundation
import Observation

/// The captain's answer on the long-pressed push: 同意 or 拒绝, sent once. The buttons wait while
/// it goes out; one that didn't reach the server can be tapped again.
@MainActor @Observable
public final class JoinRequestAnswer {
    /// Where the answer stands.
    public enum State: Equatable, Sendable {
        /// Not answered yet.
        case open
        /// Going out: `approve` is the one tapped.
        case sending(approve: Bool)
        /// 已同意: they're in.
        case approved
        /// 已拒绝.
        case declined
        /// The squad has 8 already: 同意 can't let anyone in.
        case full
        /// Answered on another phone or in the app, or withdrawn meanwhile.
        case closed
        /// The answer didn't reach the server; both buttons work again.
        case failed
    }

    public let push: JoinRequestPush
    public private(set) var state: State = .open
    @ObservationIgnored private let answerer: any JoinRequestAnswerer

    public init(push: JoinRequestPush, answerer: any JoinRequestAnswerer) {
        self.push = push
        self.answerer = answerer
    }

    /// Whether 拒绝 can be tapped now.
    public var canDecline: Bool { state == .open || state == .failed || state == .full }

    /// Whether 同意 can be tapped now: not while the squad is full.
    public var canApprove: Bool { state == .open || state == .failed }

    /// The captain taps 同意 (`approve`) or 拒绝.
    public func answer(approve: Bool) async {
        guard approve ? canApprove : canDecline else { return }
        state = .sending(approve: approve)
        do throws(DailyPushError) {
            try await answerer.answer(push.request, in: push.squad, approve: approve)
            state = approve ? .approved : .declined
        } catch .squadFull {
            state = .full
        } catch .answeredElsewhere {
            state = .closed
        } catch {
            state = .failed
        }
    }
}
