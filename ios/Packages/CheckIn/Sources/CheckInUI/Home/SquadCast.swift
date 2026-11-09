#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import Foundation
import Observation

/// Everyone on the home scene: where each teammate stands (`SquadStage`), their character and
/// what it is playing, and the cheer when I check in.
@MainActor @Observable
final class SquadCast {
    /// A teammate on the scene.
    struct Mate: Identifiable {
        let member: StageMember
        /// Their nickname; nil before they make their character.
        let name: String?
        let persona: Persona
        /// What they wear as they made their character, before their day's kit or pose.
        let look: Outfit
        /// The species whose moves their clips play with.
        let species: String?
        let player: CharacterPlayer
        /// What their character shouts in a cheer: their 口头禅, or their persona's own line.
        let line: String
        /// Their 请假条, held up on the scene.
        let disclaimer: String?
        /// The words of their latest post today, under their status in the bubble.
        let caption: String?
        var id: MemberID { member.id }
    }

    /// The squad's coach on the sideline (场边).
    struct Coach {
        let speaker: CoachSpeaker
        let player: CharacterPlayer
        /// Where its feet are.
        let spot: StagePoint
        /// As big as me, so it reads as the coach.
        var scale: Double { StageLayout.coachScale }
    }

    private(set) var stage = SquadStage(layout: .of(.gym))
    private(set) var mates: [Mate] = []
    /// The coach the squad hired; nil without one, or for a coach this build has no character for,
    /// who stays off the scene.
    private(set) var coach: Coach?
    /// The coach the squad just changed to (换教练), walking in beside `coach` while the one that
    /// left writes its letter; nil the rest of the time.
    private(set) var incoming: Coach?
    /// The coaches changing places, which `coach` and `incoming` play.
    private(set) var handover: CoachHandover?
    /// Where the coach would stand while the squad has none: an empty spot that opens 教练招聘会.
    private(set) var vacancy: StagePoint?
    /// Until when the coach's last move plays, so its whistle for news doesn't cut one short.
    @ObservationIgnored private var coachBusyUntil = Date.distantPast
    /// Bumps each time the squad cheers me, with who joins in, nearest first.
    private(set) var cheer = Cheer(count: 0, order: [])
    /// What the coach last saw on the home, for its next cue, and whose eyes they were.
    private var coachSaw: (coach: CoachID?, sighting: CoachCue.Sighting)?

    struct Cheer: Equatable {
        var count: Int
        var order: [MemberID]
    }

    /// A teammate's character and what it was made from.
    private struct Made {
        let look: Outfit
        let persona: Persona
        /// The name of the loop it plays in its pose.
        var idle: String
        let player: CharacterPlayer
    }

    private var players: [MemberID: Made] = [:]
    /// How long each teammate's doze lasts after the lights went off, at their persona's tempo:
    /// their "z z" come back after it.
    private(set) var dozes: [MemberID: Double] = [:]
    /// Each sleeper's wake-up or doze still waiting for its turn; the next pull cancels them, so
    /// a quick second pull never lets the first one's move play after it.
    private var lightsMoves: [MemberID: Task<Void, Never>] = [:]

    /// Places the squad from the store's home: everyone but `me`, and `coach` on the sideline, or,
    /// `hiring` (the squad has no coach), its empty spot there; during a `handover`, the coach
    /// that left there and the one that took over walking in.
    func update(
        home: Home, scene: SceneTheme, phase: DayPhase, coach speaker: CoachSpeaker? = nil, hiring: Bool = false,
        handover: CoachHandover? = nil
    ) {
        if stage.layout != .of(scene) { stage = SquadStage(layout: .of(scene)) }
        let standing = handover?.leaving ?? speaker
        coach = sideline(standing)
        incoming = handover.flatMap { sideline($0.coming) }
        self.handover = incoming == nil ? nil : handover
        vacancy = hiring && coach == nil && incoming == nil ? stage.layout.sideline : nil
        watch(home, by: standing)
        let teammates = home.today.members.filter { $0.member != home.member }
        let members = teammates.map { mate in
            StageMember(
                id: mate.member,
                status: StageStatus(
                    training: mate.training, activity: home.todaysSport(of: mate.member),
                    plannedRest: mate.plannedRest),
                firstCheckInAt: mate.firstCheckInAt,
                keepsToTheBack: Self.persona(of: mate) == .shy, eating: home.todaysMeal(of: mate.member))
        }
        stage.arrange(members, coach: coach != nil || incoming != nil || vacancy != nil)
        mates = zip(teammates, members).compactMap { mate, member in
            let persona = Self.persona(of: mate)
            let look = Self.look(of: mate)
            let species = PlaceholderCharacter.species(of: look)
            let pose = stage.pose(of: member, at: phase)
            let trained: Activity? = if case .trained(let activity) = member.status { activity } else { nil }
            guard let dressed = try? pose.dress(look, trained: trained, persona: persona, species: species),
                let player = player(for: member.id, wearing: dressed.outfit, persona: persona, looping: dressed.loop)
            else { return nil }
            return Mate(
                member: member, name: mate.character?.nickname.text, persona: persona, look: look, species: species,
                player: player,
                line: mate.catchphrase?.text ?? Self.personaLine(persona),
                disclaimer: home.todaysDisclaimer(of: member.id),
                caption: home.todaysCaption(of: member.id))
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

    /// Teammates who sleep at night, in the squad's order: everyone not training.
    var sleepers: [Mate] {
        mates.filter { stage.pose(of: $0.member, at: .night) == .asleep }
    }

    /// The lights went on or off at night (开灯). Switched on, each sleeper plays `woken`, one
    /// after another, into their day pose; switched off, they doze off into sleep. Under Reduce
    /// Motion their pose just swaps. Whoever trains keeps training.
    func switchLights(_ flip: LightsFlip) {
        for (index, mate) in sleepers.enumerated() {
            let pose = stage.pose(of: mate.member, at: flip.isOn ? .day : .night)
            guard let loop = try? pose.loop(persona: mate.persona, species: mate.species) else { continue }
            players[mate.id]?.idle = loop.name
            let move: Clip?
            if flip.reduceMotion {
                move = nil
            } else if flip.isOn {
                move = try? PlaceholderCharacter.woken()
            } else {
                move = try? PlaceholderCharacter.clip(for: .doze, persona: mate.persona)
            }
            if !flip.isOn { dozes[mate.id] = move?.duration ?? 0 }
            let delay = flip.start(ofSleeper: index)
            lightsMoves[mate.id]?.cancel()
            lightsMoves[mate.id] = Task { @MainActor in
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return }
                try? mate.player.wear(mate.player.figure, idle: loop)
                if let move { try? mate.player.play(move) }
            }
        }
    }

    /// What the first sleeper mumbles when the lights wake them, by persona (the approved 开灯).
    static func wokenLine(_ persona: Persona) -> String {
        switch persona {
        case .deadpan: String(localized: "……谁开的灯", bundle: .module.inAppLanguage)
        case .energetic: String(localized: "谁啊！", bundle: .module.inAppLanguage)
        case .shy: String(localized: "…好亮", bundle: .module.inAppLanguage)
        case .drama: String(localized: "我的美容觉！！", bundle: .module.inAppLanguage)
        case .showoff: String(localized: "关了关了", bundle: .module.inAppLanguage)
        }
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

    /// The coach on this scene's sideline, its character made once per coach: the one that walked
    /// in keeps its own as it steps onto the spot.
    private func sideline(_ speaker: CoachSpeaker?) -> Coach? {
        guard let speaker, let spot = stage.layout.sideline else { return nil }
        if let made = [coach, incoming].compactMap { $0 }.first(where: { $0.speaker.id == speaker.id }) {
            return Coach(speaker: speaker, player: made.player, spot: spot)
        }
        let id = speaker.id.rawValue
        guard CoachCharacter.exists(id),
            let player = try? CharacterPlayer(
                figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
        else { return nil }
        return Coach(speaker: speaker, player: player, spot: spot)
    }

    /// The coach gives its pep talk, when tapped: its 战术板 line is on the 简历 the tap opens.
    func coachTalks() {
        play(.pepTalk)
    }

    /// The coach claps for its challenge marked done (我完成了).
    func coachClaps() {
        play(.clap)
    }

    /// The coach whistles at a post that arrived and claps at a week that reached its goal, as
    /// the home changes under it; it lands as my ring closes, when the post is mine.
    private func watch(_ home: Home, by speaker: CoachSpeaker?) {
        let now = CoachCue.Sighting(home)
        let before = coachSaw?.coach == speaker?.id ? coachSaw?.sighting : nil
        coachSaw = (speaker?.id, now)
        guard let cue = CoachCue.after(before, now: now) else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Motion.ringFill))
            self?.play(cue == .clap ? .clap : .whistle)
        }
    }

    /// The coach whistles because its page has news, unless another of its moves is still playing
    /// or the coaches are changing places.
    func coachWhistlesForNews(now: Date = .now) {
        guard handover == nil, now >= coachBusyUntil else { return }
        play(.whistle, now: now)
    }

    private func play(_ move: CoachCharacter.Move, now: Date = .now) {
        guard let coach, let clip = try? CoachCharacter.clip(move, coach: coach.speaker.id.rawValue),
            (try? coach.player.play(clip, now: now)) != nil
        else { return }
        coachBusyUntil = now.addingTimeInterval(clip.duration)
    }

    /// The member's character, made again when what they wear or their persona changes (a kit
    /// once they trained); when only their pose does, it carries on from the pose on screen
    /// into the new loop.
    private func player(
        for member: MemberID, wearing look: Outfit, persona: Persona, looping idle: Clip
    ) -> CharacterPlayer? {
        if let existing = players[member], existing.look == look, existing.persona == persona {
            if existing.idle != idle.name, (try? existing.player.wear(existing.player.figure, idle: idle)) != nil {
                players[member]?.idle = idle.name
            }
            return existing.player
        }
        guard let figure = try? PlaceholderCharacter.figure(wearing: look),
            let player = try? CharacterPlayer(figure: figure, idle: idle)
        else { return nil }
        players[member] = Made(look: look, persona: persona, idle: idle.name, player: player)
        return player
    }

    /// The persona the member picked, or a stand-in before they made their character.
    static func persona(of mate: SquadmateToday) -> Persona {
        mate.character.map { Persona($0.look) } ?? StandInCharacter.persona(of: mate.member)
    }

    /// The look the member made, or a stand-in before they made their character.
    static func look(of mate: SquadmateToday) -> Outfit {
        mate.character.map { Outfit($0.look) } ?? StandInCharacter.look(of: mate.member)
    }

    /// The line a persona shouts when its member hasn't set a 口头禅 (spec rev 221).
    static func personaLine(_ persona: Persona) -> String {
        switch persona {
        case .energetic: String(localized: "冲冲冲！", bundle: .module.inAppLanguage)
        case .showoff: String(localized: "看我！", bundle: .module.inAppLanguage)
        case .drama: String(localized: "泪目了", bundle: .module.inAppLanguage)
        case .deadpan: String(localized: "可以", bundle: .module.inAppLanguage)
        case .shy: String(localized: "（小声）加油", bundle: .module.inAppLanguage)
        }
    }
}
#endif
