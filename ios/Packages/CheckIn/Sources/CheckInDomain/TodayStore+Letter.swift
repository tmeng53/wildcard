import Contracts
import Foundation

/// 换教练 on 今天 (the approved 教练交接信, version 3): the coach that left stays on the sideline
/// writing its letter under 「交接中」 while the one that took over waits beside it, for as long as
/// the letter takes (Tracy, 2026-11-08: no time limit); written, the envelope flies out, and the
/// coaches swap either way. Every member opens a new letter once on each phone.
extension TodayStore {
    /// 确认换教练 landed: the coaches swap on the sideline once the coach that left wrote its
    /// letter or couldn't (`writeLetter()`). False when there is nothing to swap.
    @discardableResult
    public func beginHandover(from leaving: CoachSpeaker, to coming: CoachSpeaker) -> Bool {
        guard savedHome != nil, leaving.id != coming.id else { return false }
        handover = CoachHandover(from: leaving, to: coming, start: now())
        return true
    }

    /// Has the coach that left write its letter, however long it takes; a letter that couldn't be
    /// written swaps the coaches all the same, without one.
    public func writeLetter() async {
        guard let started = handover, started.end == nil, let squad = savedHome?.squad.id else { return }
        await loadOpenedLetter()
        let letter = (try? await backend.writeLetter(in: squad)) ?? nil
        guard handover?.start == started.start, handover?.coming == started.coming else { return }
        handover?.end(at: now(), letter: letter?.recipient.id == started.coming.id ? letter : nil)
    }

    /// The swap has played out: the coach that took over stands on the sideline, with its letter.
    public func finishHandover() {
        guard let handover, handover.end != nil else { return }
        self.handover = nil
        guard let home = savedHome,
            loadedCoach?.coach?.coach.id != handover.coming.id || loadedCoach?.squad != home.squad.id
        else { return }
        loadedCoach = (home.squad.id, SidelineCoach(coach: handover.coming, note: nil, letter: handover.letter))
    }

    /// The letter on 今天 now: one opened again from 通知 or the 简历, else a new one this phone
    /// hasn't opened, sealed: the one just written, once its coach threw it, or the one the squad's
    /// coach was left.
    public var letter: ShownLetter? {
        if let letterAgain { return ShownLetter(letter: letterAgain, isSealed: false) }
        let new: CoachLetter? =
            if let handover { handover.end == nil ? nil : handover.letter } else { coach?.letter }
        guard let new, !isOpened(new) else { return nil }
        return ShownLetter(letter: new, isSealed: true)
    }

    /// The letter the squad's coach was left when it took over, for its 简历 to open again.
    public var coachLetter: CoachLetter? { handover == nil ? coach?.letter : nil }

    /// 收下: the letter goes, and this phone never opens it by itself again.
    public func putAwayLetter() async {
        guard let shown = letter else { return }
        letterAgain = nil
        guard shown.isSealed else { return }
        openedLetterID = max(openedLetterID ?? 0, shown.letter.id)
        await backend.opened(shown.letter)
    }

    /// Opens a letter again, from its row in 通知 or the coach's 简历.
    public func showAgain(_ letter: CoachLetter) {
        letterAgain = letter
    }

    /// Reads which letter this phone opened last, before a load shows the squad's coach's.
    func loadOpenedLetter() async {
        if openedLetterID == nil { openedLetterID = await backend.openedLetter() }
    }

    private func isOpened(_ letter: CoachLetter) -> Bool {
        guard let openedLetterID else { return false }
        return letter.id <= openedLetterID
    }
}

/// A letter on 今天: sealed in its envelope while it is new, else open.
public struct ShownLetter: Hashable, Sendable {
    public let letter: CoachLetter
    /// New on this phone: it flies in in its envelope, opened by a tap on the seal.
    public let isSealed: Bool

    public init(letter: CoachLetter, isSealed: Bool) {
        self.letter = letter
        self.isSealed = isSealed
    }
}
