import Contracts
import DesignSystemUI
import Foundation
import SquadDomain

/// A squad kept in memory, for previews, UI tests and the sample squad.
public actor InMemorySquadSettingsService: SquadSettingsService {
    /// Who the member is on the sample squad.
    public enum Seat: String, Sendable, CaseIterable {
        /// 小林, the captain; Coco won last week's crown and picks.
        case captain
        /// Coco, who won last week's crown and picks the scene.
        case winner
        /// Mia, who manages nobody and picks nothing.
        case member
        /// 小林, the captain, with nobody holding last week's crown: the captain picks.
        case noWinner
        /// 小林, the captain, whose squad has hired 毛头.
        case coached
        /// Mia, on a squad that has hired 毛头: she reads its 简历 and hires nobody.
        case coachedMember
    }

    private var current: SquadSettings
    private let failsSaving: Bool

    public init(settings: SquadSettings, failsSaving: Bool = false) {
        current = settings
        self.failsSaving = failsSaving
    }

    /// The squad the page is reviewed against: 晨跑五人组, five members, 小林 captain, on the
    /// track. `longNames` gives everyone the longest name the rules allow, for layout tests.
    public static func sample(seat: Seat = .captain, longNames: Bool = false) -> InMemorySquadSettingsService {
        let ids = (1...5).map {
            MemberID(UUID(uuidString: String(format: "a0000000-0000-4000-8000-%012d", $0)) ?? UUID())
        }
        let names =
            longNames
            ? (1...5).map { String(repeating: "长", count: Nickname.maxLength - 1) + "\($0)" }
            : ["小林", "Coco", "Mia", "阿杰", "大卫"].map {
                String(copyKey: $0, bundle: Bundle.module)
            }
        var characters: [MemberID: MemberCharacter] = [:]
        for (id, (name, look)) in zip(ids, zip(names, sampleLooks)) {
            if let nickname = try? Nickname(name) { characters[id] = MemberCharacter(nickname: nickname, look: look) }
        }
        let squadName =
            longNames
            ? String(repeating: "超", count: SquadName.maxLength)
            : String(copyKey: "晨跑五人组", bundle: Bundle.module)
        let viewer: MemberID =
            switch seat {
            case .captain, .noWinner, .coached: ids[0]
            case .winner: ids[1]
            case .member, .coachedMember: ids[2]
            }
        let coached = seat == .coached || seat == .coachedMember
        let now = Date.now
        let pickers: SquadScene.Pickers = seat == .noWinner ? .captain(ids[0]) : .crown([ids[1]])
        let week = LocalDay(at: now, in: .current).weekStart
        return InMemorySquadSettingsService(
            settings: SquadSettings(
                squad: Squad(
                    id: SquadID(UUID()), name: squadName, inviteCode: "K7Q2M9PX", members: ids, captain: ids[0]),
                viewer: viewer, characters: characters,
                scene: SquadScene(
                    week: week, scene: .gym, pickers: pickers, picked: nil,
                    canPick: pickers.members.contains(viewer),
                    history: [
                        SceneHistory(scene: .track, weeksAgo: 2), SceneHistory(scene: .pool, weeksAgo: nil),
                        SceneHistory(scene: .gym, weeksAgo: 0), SceneHistory(scene: .tennis, weeksAgo: nil),
                        SceneHistory(scene: .climbing, weeksAgo: nil),
                    ]),
                coach: SquadCoach(
                    hire: coached ? SquadCoach.Hire(coach: sampleCoach, since: now) : nil, canHire: viewer == ids[0]),
                today: LocalDay(at: now, in: .current), timeZone: .current,
                goal: SquadWeeklyGoal(
                    daysPerMember: 3, nextDaysPerMember: 3, canChange: viewer == ids[0],
                    recent: SquadWeeklyGoal.Recent(weeks: 4, daysPerMember: 3.4)),
                matchTimeZone: SquadTimeZone(
                    timeZone: "Asia/Taipei", canChange: viewer == ids[0]),
                language: SquadLanguage(language: .simplifiedChinese, canChange: viewer == ids[0])))
    }

    public func settings() async throws(SquadError) -> SquadSettings {
        current
    }

    public func rename(_ squad: SquadID, to name: SquadName) async throws(SquadError) -> Squad {
        if failsSaving { throw .unavailable }
        current.squad = current.squad.with(name: name.text)
        return current.squad
    }

    public func handCaptaincy(of squad: SquadID, to member: MemberID) async throws(SquadError) -> Squad {
        if failsSaving { throw .unavailable }
        current.squad = current.squad.with(captain: member)
        if case .captain = current.scene.pickers {
            current.scene.pickers = .captain(member)
            current.scene.canPick = member == current.viewer && current.scene.picked == nil
        }
        return current.squad
    }

    public func remove(_ member: MemberID, from squad: SquadID) async throws(SquadError) {
        if failsSaving { throw .unavailable }
        let left = current.squad.members.filter { $0 != member }
        let captain = current.squad.captain == member ? left.first : current.squad.captain
        current.squad = current.squad.with(members: left).with(captain: captain)
    }

    public func pick(_ scene: SceneID, for squad: SquadID, week: LocalDay) async throws(SquadError) -> SquadScene {
        if failsSaving { throw .unavailable }
        guard current.scene.canPick else { throw .outdated }
        current.scene.scene = scene
        current.scene.picked = SquadScene.Pick(scene: scene, picker: current.viewer)
        current.scene.canPick = false
        current.scene.history = current.scene.history.map { entry in
            SceneHistory(scene: entry.scene, weeksAgo: entry.scene == scene ? 0 : entry.weeksAgo)
        }
        return current.scene
    }
}

extension InMemorySquadSettingsService {
    public func coaches() async throws(SquadError) -> [Coach] {
        sampleCoaches
    }

    public func hire(_ coach: CoachID, for squad: SquadID) async throws(SquadError) -> SquadCoach {
        if failsSaving { throw .unavailable }
        guard current.coach.canHire, let hired = sampleCoaches.first(where: { $0.id == coach }) else {
            throw .outdated
        }
        if current.coach.hire?.coach.id != coach {
            current.coach = SquadCoach(hire: .init(coach: hired, since: .now), canHire: true)
        }
        return current.coach
    }

    public func setWeeklyGoal(of squad: SquadID, to daysPerMember: Int) async throws(SquadError) -> SquadWeeklyGoal {
        if failsSaving { throw .unavailable }
        guard current.goal.canChange, SquadWeeklyGoal.choices.contains(daysPerMember) else { throw .outdated }
        current.goal.nextDaysPerMember = daysPerMember
        return current.goal
    }

    public func setTimeZone(of squad: SquadID, to timeZone: String) async throws(SquadError) -> SquadTimeZone {
        if failsSaving { throw .unavailable }
        guard current.matchTimeZone.canChange, TimeZone(identifier: timeZone) != nil else { throw .outdated }
        current.matchTimeZone = SquadTimeZone(timeZone: timeZone, canChange: true)
        return current.matchTimeZone
    }

    public func setLanguage(of squad: SquadID, to language: SquadLanguage.Language) async throws(SquadError)
        -> SquadLanguage
    {
        if failsSaving { throw .unavailable }
        guard current.language.canChange else { throw .outdated }
        current.language.language = language
        return current.language
    }

    public func fireCoach(of squad: SquadID) async throws(SquadError) -> SquadCoach {
        if failsSaving { throw .unavailable }
        guard current.coach.canHire else { throw .outdated }
        current.coach = SquadCoach(hire: nil, canHire: true)
        return current.coach
    }
}

/// The first coach, 毛头, with the 简历 Tracy approved (2026-11-01). The words are the API's, so
/// they stay as the server sends them.
private let sampleCoach = Coach(
    id: "xiaohun", name: "毛头", title: "混混教练", catchphrase: "先动起来，证书以后再说",
    background: "体育学院刚毕业，该学的都学了，就是证还没考下来", yearsCoaching: 0, experience: "热情满格",
    style: "懂行、松弛、风趣", tags: ["体院应届", "懂行", "松弛", "风趣"], pay: "管饭就行")

/// The second coach, 帕帕, a smiling follow-along coach whose 「最后八个」 never ends (Tracy, 2026-11-08).
private let sampleCoaches = [
    sampleCoach,
    Coach(
        id: "papa", name: "帕帕", title: "跟练教练", catchphrase: "马了等于做了，收藏等于瘦了",
        background: "跟练视频收藏的人比练的人多，评论区一半在打卡第一天", yearsCoaching: 5,
        experience: "个人纪录：一组「最后八个」做了 64 个", style: "全程微笑，一口气不歇，像个人形 AI",
        tags: ["持证上岗", "跟练", "高强度", "爱笑"], pay: "先把你收藏夹里的练完"),
]

extension Squad {
    fileprivate func with(name: String? = nil, members: [MemberID]? = nil) -> Squad {
        Squad(
            id: id, name: name ?? self.name, inviteCode: inviteCode, members: members ?? self.members, captain: captain)
    }

    fileprivate func with(captain: MemberID?) -> Squad {
        Squad(id: id, name: name, inviteCode: inviteCode, members: members, captain: captain)
    }
}

/// The sample squad's looks, one each, so the page shows a squad of different characters.
private let sampleLooks: [CharacterLook] = [
    CharacterLook(
        persona: "energetic",
        variants: ["body": "peach", "hair": "long", "top": "warmup-tank", "bottom": "warmup-shorts"]),
    CharacterLook(
        persona: "drama",
        variants: ["body": "lop", "top": "warmup-hoodie", "bottom": "warmup-leggings"]),
    CharacterLook(
        persona: "deadpan", variants: ["body": "calico", "cheeks": "rosy", "top": "warmup-tee", "bottom": "moss-cargo"]),
    CharacterLook(
        persona: "energetic",
        variants: ["body": "peach", "hair": "curls", "top": "warmup-tee", "bottom": "warmup-shorts"],
        colors: ["body": "#C68A5E"]),
    CharacterLook(
        persona: "shy",
        variants: ["body": "shiba", "cheeks": "rosy", "top": "nolook-jersey", "bottom": "warmup-shorts"]),
]
