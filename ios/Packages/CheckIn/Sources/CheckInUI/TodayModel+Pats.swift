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

    /// A teammate on the scene was tapped: they hop, and their card opens with their today and
    /// 「拍一拍」 over it.
    func tapMate(_ id: MemberID) {
        guard let mate = cast.mates.first(where: { $0.id == id }),
            pats.tap(mate, cast: cast, phase: stagePhase) != nil
        else { return }
        openTeammate(id)
    }

    /// What `member` is up to today, as the home shows them (睡着了 while asleep on the scene),
    /// for the 今天 line over their card; nil for someone the home doesn't show.
    func today(of member: MemberID) -> MateToday? {
        guard let home else { return nil }
        if member == home.member {
            let line = PatStage.status(
                StageStatus(
                    training: store.myStatus, activity: home.todaysSport(of: member),
                    plannedRest: home.mine?.plannedRest ?? false),
                eating: home.todaysMeal(of: member, at: Timestamp(now())),
                caption: home.todaysCaption(of: member, at: Timestamp(now())),
                disclaimer: home.todaysDisclaimer(of: member), asleep: myPose(at: stagePhase) == .asleep)
            return MateToday(title: line.title, detail: line.detail, isMe: true)
        }
        guard let mate = cast.mates.first(where: { $0.id == member }) else { return nil }
        let line = PatStage.status(
            mate.member.status, eating: mate.member.eating, caption: mate.caption, disclaimer: mate.disclaimer,
            asleep: cast.stage.pose(of: mate.member, at: stagePhase) == .asleep)
        return MateToday(title: line.title, detail: line.detail, isMe: false)
    }

    /// Whether I can still pat `id` today.
    func canPat(_ id: MemberID) -> Bool {
        store.canPat(id)
    }

    /// I pat a teammate from their card or their bubble: it plays at once and goes to the server,
    /// once a day.
    func patMate(_ id: MemberID) {
        guard store.canPat(id), !isChanging, together.playing == nil,
            let mate = cast.mates.first(where: { $0.id == id })
        else { return }
        guard pats.pat(mate, mine: player) else { return }
        Task { try? await store.pat(id) }
    }

    /// The key under which the latest pat already shown to `member` is kept, apart for each
    /// account signed in on this phone.
    private static let replayPatsKey = "today.replayPatsOnMe"

    private static func patsShownKey(for member: MemberID) -> String {
        "today.patsShownUntil.\(member)"
    }

    /// The 6pm push was opened: everyone who patted me in the last day pats me again, even if
    /// those pats already played on this phone; at once when the home is in, else as it opens.
    public func replayPatsOnMe() {
        // Kept until the home has loaded, which may be after a launch the push itself started.
        defaults.set(true, forKey: Self.replayPatsKey)
        guard store.home != nil else { return }
        Task { await playPatsOnMe() }
    }

    /// Whoever patted me since the last pat shown pats me now, from where they stand: the
    /// earliest, with the next one named on their bubble. Each pat plays once on this phone,
    /// unless the 6pm push was opened (`replayPatsOnMe`), which plays the day's again.
    func playPatsOnMe() async {
        guard let member = store.home?.member else { return }
        let replays = defaults.bool(forKey: Self.replayPatsKey)
        defaults.removeObject(forKey: Self.replayPatsKey)
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
