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
                Bundle.module.inAppLanguage.localizedString(forKey: $0, value: nil, table: nil)
            }
        var characters: [MemberID: MemberCharacter] = [:]
        for (id, (name, look)) in zip(ids, zip(names, sampleLooks)) {
            if let nickname = try? Nickname(name) { characters[id] = MemberCharacter(nickname: nickname, look: look) }
        }
        let squadName =
            longNames
            ? String(repeating: "超", count: SquadName.maxLength)
            : Bundle.module.inAppLanguage.localizedString(forKey: "晨跑五人组", value: nil, table: nil)
        let viewer: MemberID =
            switch seat {
            case .captain, .noWinner: ids[0]
            case .winner: ids[1]
            case .member: ids[2]
            }
        let pickers: SquadScene.Pickers = seat == .noWinner ? .captain(ids[0]) : .crown([ids[1]])
        let week = LocalDay(at: .now, in: .current).weekStart
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
                    ])))
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
    CharacterLook(persona: "drama", variants: ["body": "lop", "top": "warmup-hoodie", "bottom": "warmup-leggings"]),
    CharacterLook(persona: "deadpan", variants: ["body": "calico", "top": "warmup-tee", "bottom": "moss-cargo"]),
    CharacterLook(
        persona: "energetic",
        variants: ["body": "peach", "hair": "curls", "top": "warmup-tee", "bottom": "warmup-shorts"],
        colors: ["body": "#C68A5E"]),
    CharacterLook(persona: "shy", variants: ["body": "shiba", "top": "nolook-jersey", "bottom": "warmup-shorts"]),
]
