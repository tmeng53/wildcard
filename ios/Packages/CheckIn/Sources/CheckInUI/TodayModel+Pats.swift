#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation

/// 拍一拍 on the home, and the squad's news told on the scene.
extension TodayModel {
    /// The squad's news since the home was last shown, once: who joined walks in with a bubble,
    /// and a member made captain hears 「你现在是队长了」. Leaving says nothing. Kept for the next
    /// load while the scene is covered (writing a check-in, the burst open).
    func tellNews() async {
        guard !store.news.isEmpty else { return }
        try? await Task.sleep(for: .seconds(PatStage.patMeDelay))
        await untilArrived()
        guard step == .scene, !isBurstOpen else { return }
        let news = store.takeNews()
        guard !news.isEmpty else { return }
        let joined = news.joined.compactMap { id in cast.mates.first { $0.id == id } }
        pats.welcome(joined, cast: cast, phase: stagePhase)
        if news.madeCaptain { pats.say(String(localized: "你现在是队长了", bundle: .module.inAppLanguage)) }
        // A pat on me waits until the news has been read.
        try? await Task.sleep(for: .seconds(pats.hold))
    }

    /// A teammate on the scene was tapped: their status and 「拍一拍」.
    func tapMate(_ id: MemberID) {
        guard let mate = cast.mates.first(where: { $0.id == id }) else { return }
        pats.tap(mate, cast: cast, phase: stagePhase)
    }

    /// Whether I can still pat `id` today.
    func canPat(_ id: MemberID) -> Bool {
        store.canPat(id)
    }

    /// I pat a teammate from their bubble: it plays at once and goes to the server, once a day.
    func patMate(_ id: MemberID) {
        guard store.canPat(id), !isChanging, together.playing == nil,
            let mate = cast.mates.first(where: { $0.id == id })
        else { return }
        guard pats.pat(mate, mine: player) else { return }
        Task { try? await store.pat(id) }
    }

    /// The key under which the latest pat already shown to `member` is kept, apart for each
    /// account signed in on this phone.
    private static func patsShownKey(for member: MemberID) -> String {
        "today.patsShownUntil.\(member)"
    }

    /// The 6pm push was tapped: on the next open, everyone who patted me today pats me again,
    /// even if those pats already played on this phone.
    public func replayPatsOnMe() {
        replaysPatsOnMe = true
    }

    /// Whoever patted me since the last pat shown pats me now, from where they stand: the
    /// earliest, with the next one named on their bubble. Each pat plays once on this phone,
    /// unless the 6pm push was tapped (`replayPatsOnMe`), which plays the day's pats again.
    func playPatsOnMe() async {
        guard let member = store.home?.member else { return }
        let replays = replaysPatsOnMe
        replaysPatsOnMe = false
        let shown = replays ? 0 : defaults.double(forKey: Self.patsShownKey(for: member))
        let fresh = store.pokes.received.filter { Double($0.patAt.millisecondsSince1970) > shown }
        let patters = fresh.compactMap { pat in cast.mates.first { $0.id == pat.from } }
        guard let latest = fresh.last, let first = patters.first else { return }
        try? await Task.sleep(for: .seconds(PatStage.patMeDelay))
        await untilArrived()
        guard pats.patMe(by: first, others: Array(patters.dropFirst()), mine: player, myPersona: myPersona)
        else { return }
        defaults.set(Double(latest.patAt.millisecondsSince1970), forKey: Self.patsShownKey(for: member))
    }
}
#endif
