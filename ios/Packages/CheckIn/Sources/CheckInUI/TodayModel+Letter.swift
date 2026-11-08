#if os(iOS)
import CheckInDomain
import Contracts
import Foundation

/// 换教练 on 今天 and the coach's letter (交接信, the approved 教练交接信 version 3): after the
/// captain confirms, the coach that left writes on the sideline under 「交接中」 for as long as the
/// letter takes, with the one that took over waiting beside it; then they change places and, when
/// it was written, the envelope flies out. A new letter opens once on each phone; 通知 and the
/// coach's 简历 open it again.
extension TodayModel {
    /// 确认换教练 landed, from `leaving` to `coming`: the swap plays on the sideline while the
    /// letter is written, and ends with `coming` standing there.
    public func handOver(from leaving: CoachSpeaker, to coming: CoachSpeaker) {
        Task { @MainActor in
            // Changed from 小队 before 今天 ever loaded: the squad comes first.
            if home == nil { await load() }
            guard store.beginHandover(from: leaving, to: coming) else { return }
            isBurstOpen = false
            placeSquad()
            await store.writeLetter()
            placeSquad()
            guard let handover = store.handover, let finishes = handover.finishesAt else { return }
            let left = finishes.timeIntervalSince(now())
            if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            guard store.handover?.start == handover.start else { return }
            store.finishHandover()
            placeSquad()
        }
    }

    /// The letter over 今天 now, once the scene is free for it: not while a check-in is being
    /// written, the burst is open or the squad is dropping in.
    var shownLetter: ShownLetter? {
        guard step == .scene, !isBurstOpen, arrival == nil else { return nil }
        return store.letter
    }

    /// When the letter on 今天 starts flying in: as its coach leaves, or now.
    var letterShownAt: Date { store.handover?.envelopeAt ?? now() }

    /// 收下.
    func putAwayLetter() {
        Task { await store.putAwayLetter() }
    }

    /// Opens a letter again, from its row in 通知 or the coach's 简历.
    public func showAgain(_ letter: CoachLetter) {
        store.showAgain(letter)
    }

    /// The letter the squad's coach was left when it took over, for its 简历.
    public var coachLetter: CoachLetter? { store.coachLetter }
}
#endif
