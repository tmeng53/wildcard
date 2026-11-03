#if os(iOS)
import CheckInDomain
import Contracts
import Foundation

/// The coach on the home's sideline: it says the day's 战术板 line by itself the first time the
/// home opens that day on this phone, holds it 6 seconds, and says it again when tapped.
extension TodayModel {
    /// The approved 6 seconds.
    static let coachLineHold = 6.0

    /// The key under which the latest line already said by itself to `member` is kept, apart for
    /// each account signed in on this phone.
    private static func coachLineShownKey(for member: MemberID) -> String {
        "today.coachLineShown.\(member)"
    }

    /// Says the day's line once on this phone, after the squad's news and pats.
    func sayCoachLine() async {
        guard let member = store.home?.member, let line = store.coachLine, cast.coach != nil else { return }
        let key = Self.coachLineShownKey(for: member)
        let said = line.writtenAt.timeIntervalSince1970
        guard defaults.double(forKey: key) < said else { return }
        await untilArrived()
        guard step == .scene, !isBurstOpen else { return }
        defaults.set(said, forKey: key)
        say(line)
    }

    /// The coach was tapped: it cheers and says the day's line again, if it has one.
    func tapCoach() {
        guard arrival == nil else { return }
        cast.cheerCoach()
        if let line = store.coachLine { say(line) }
    }

    /// Puts `line` in the coach's bubble for its hold.
    private func say(_ line: CoachNote) {
        coachHold?.cancel()
        coachSays = line
        coachHold = Task { @MainActor [weak self, coachLineHold] in
            try? await Task.sleep(for: .seconds(coachLineHold))
            guard !Task.isCancelled else { return }
            self?.coachSays = nil
        }
    }
}
#endif
