#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import Foundation
import Observation

/// Everyone on the home scene: where each teammate stands (`SquadStage`), their character and
/// what it is playing, and the cheer when I check in.
@MainActor @Observable
final class SquadCast {
    /// A teammate on the scene.
    struct Mate: Identifiable {
        let member: StageMember
        let persona: Persona
        /// The species whose moves their clips play with.
        let species: String?
        let player: CharacterPlayer
        /// What their character shouts in a cheer: their 口头禅, or their persona's own line.
        let line: String
        /// Their 请假条, held up on the scene.
        let disclaimer: String?
        var id: MemberID { member.id }
    }

    private(set) var stage = SquadStage(layout: .of(.gym))
    private(set) var mates: [Mate] = []
    /// Bumps each time the squad cheers me, with who joins in, nearest first.
    private(set) var cheer = Cheer(count: 0, order: [])

    struct Cheer: Equatable {
        var count: Int
        var order: [MemberID]
    }

    private var players: [MemberID: (look: Outfit, persona: Persona, player: CharacterPlayer)] = [:]

    /// Places the squad from the store's home: everyone but `me`.
    func update(home: Home, scene: SceneTheme, phase: DayPhase) {
        if stage.layout != .of(scene) { stage = SquadStage(layout: .of(scene)) }
        let teammates = home.today.members.filter { $0.member != home.member }
        let members = teammates.map { mate in
            StageMember(
                id: mate.member,
                status: StageStatus(
                    training: mate.training, activity: home.todaysSport(of: mate.member),
                    plannedRest: mate.plannedRest),
                firstCheckInAt: mate.firstCheckInAt,
                keepsToTheBack: Self.persona(of: mate) == .shy)
        }
        stage.arrange(members)
        mates = zip(teammates, members).compactMap { mate, member in
            let persona = Self.persona(of: mate)
            let look = Self.look(of: mate)
            let species = PlaceholderCharacter.species(of: look)
            guard let player = player(for: member.id, wearing: look, persona: persona, species: species)
            else { return nil }
            return Mate(
                member: member, persona: persona, species: species, player: player,
                line: mate.catchphrase?.text ?? Self.personaLine(persona),
                disclaimer: home.todaysDisclaimer(of: member.id))
        }
    }

    /// The squad turns to me and cheers, each persona at its own beat (the 高能量 first, the 淡人
    /// last); anyone training keeps going. The one strong moment of a 练了.
    func cheerMe(at phase: DayPhase) {
        let cheering = stage.cheerers(mates.map(\.member), at: phase)
            .compactMap { id in mates.first { $0.id == id } }
            .sorted { Self.cheerDelay($0.persona) < Self.cheerDelay($1.persona) }
        for mate in cheering {
            guard let clip = try? PlaceholderCharacter.clip("cheer", persona: mate.persona, species: mate.species)
            else { continue }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.cheerDelay(mate.persona)))
                try? mate.player.play(clip)
            }
        }
        cheer = Cheer(count: cheer.count + 1, order: cheering.map(\.id))
    }

    /// How long after my ring closes each persona starts cheering, from the approved home.
    static func cheerDelay(_ persona: Persona) -> Double {
        switch persona {
        case .energetic: 0.05
        case .showoff: 0.15
        case .drama: 0.2
        case .shy: 0.55
        case .deadpan: 0.9
        }
    }

    /// The member's character, made again when their look or persona changes.
    private func player(for member: MemberID, wearing look: Outfit, persona: Persona, species: String?)
        -> CharacterPlayer?
    {
        if let existing = players[member], existing.look == look, existing.persona == persona {
            return existing.player
        }
        // The persona's idle, which everyone plays until the sport, sitting, sign and sleeping
        // moves land; the scene adds the sign and the sleep.
        guard let figure = try? PlaceholderCharacter.figure(wearing: look),
            let clip = try? PlaceholderCharacter.clip("idle", persona: persona, species: species),
            let player = try? CharacterPlayer(figure: figure, idle: clip)
        else { return nil }
        players[member] = (look, persona, player)
        return player
    }

    /// The persona the member picked, or a stand-in before they made their character.
    static func persona(of mate: SquadmateToday) -> Persona {
        mate.character.map { Persona($0.look) } ?? persona(of: mate.member)
    }

    /// The look the member made, or a stand-in before they made their character.
    static func look(of mate: SquadmateToday) -> Outfit {
        mate.character.map { Outfit($0.look) } ?? look(of: mate.member)
    }

    // MARK: Stand-ins for a member who hasn't made their character yet.

    /// A persona per member, the same on every launch.
    static func persona(of member: MemberID) -> Persona {
        Persona.allCases[seed(member, 0) % Persona.allCases.count]
    }

    /// A look per member, the same on every launch.
    static func look(of member: MemberID) -> Outfit {
        func pick(_ slot: Slot, _ salt: Int) -> String? {
            let variants = PlaceholderCharacter.variants(for: slot)
            return variants.isEmpty ? nil : variants[seed(member, salt) % variants.count]
        }
        var variants: [Slot: String] = ["body": "peach", "brows": "soft", "cheeks": "rosy"]
        variants["hair"] = pick("hair", 1)
        variants["top"] = pick("top", 2)
        variants["bottom"] = pick("bottom", 3)
        var colors: [Slot: RGBAColor] = [:]
        for (salt, slot) in [Slot("body"), "hair", "top", "bottom"].enumerated() {
            guard let variant = variants[slot] else { continue }
            let swatches = PlaceholderCharacter.swatches(for: slot, wearing: variant)
            if !swatches.isEmpty { colors[slot] = swatches[seed(member, salt + 4) % swatches.count] }
        }
        return Outfit(variants, colors: colors)
    }

    private static func seed(_ member: MemberID, _ salt: Int) -> Int {
        let bytes = withUnsafeBytes(of: member.uuid.uuid) { Array($0) }
        return Int(bytes[(salt * 3) % bytes.count]) &+ Int(bytes[(salt * 3 + 1) % bytes.count]) &* 7
    }

    /// The line a persona shouts when its member hasn't set a 口头禅 (spec rev 221).
    static func personaLine(_ persona: Persona) -> String {
        switch persona {
        case .energetic: String(localized: "冲冲冲！", bundle: .module)
        case .showoff: String(localized: "看我！", bundle: .module)
        case .drama: String(localized: "泪目了", bundle: .module)
        case .deadpan: String(localized: "可以", bundle: .module)
        case .shy: String(localized: "（小声）加油", bundle: .module)
        }
    }
}
#endif
