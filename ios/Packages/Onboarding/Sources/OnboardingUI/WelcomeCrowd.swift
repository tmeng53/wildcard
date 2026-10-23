#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CharacterEditorDomain
import CharacterEditorUI
import Foundation
import Observation

/// The open screen's five characters, the looks they change between, and what they do after
/// the sprint: cheer the finish, then a check-in each, once.
@MainActor @Observable
final class WelcomeCrowd {
    struct Spot {
        let centerX: Double
        /// How far above the bottom of the screen's free area, over the sign-in button.
        let feetAbove: Double
        let width: Double
        /// What this one does once the cheering is over.
        let checkIn: CheckInMove
    }

    /// One look the crowd can show: its figure, persona and player, built once.
    private struct Member {
        let outfit: Outfit
        let persona: Persona
        let figure: Figure
        let idle: Clip
        let player: CharacterPlayer
    }

    /// The design's points, on a 390-point-wide screen: two back, three in front, standing up
    /// from the sign-in button so it never covers their feet, however tall the phone is. At the
    /// back the left one naps (请假条) and the right one lifts (练了); in front a salad (健康餐), a
    /// lift in the middle and a boba (坦白放纵餐).
    static let designWidth = 390.0
    let spots = [
        Spot(centerX: 122, feetAbove: 129, width: 96, checkIn: .excuse),
        Spot(centerX: 268, feetAbove: 129, width: 96, checkIn: .workout),
        Spot(centerX: 62, feetAbove: 53, width: 112, checkIn: .healthyMeal),
        Spot(centerX: 195, feetAbove: 39, width: 132, checkIn: .workout),
        Spot(centerX: 328, feetAbove: 53, width: 112, checkIn: .treatMeal),
    ]
    /// The middle one, whose look 角色和昵称 starts from.
    static let middle = 3
    /// Who changes next, round and round: the middle first.
    static let order = [3, 0, 4, 2, 1]
    /// Who cheers and checks in first after the break: the middle, then the front, then the back.
    static let cheerOrder = [3, 2, 4, 0, 1]
    /// After the break: the first cheer, then one every `cheerStagger`; the check-ins start at
    /// `checkInsStart`, one every `checkInStagger`; the first change of look at `firstChange`,
    /// then one every `interval`. Without the sprint they count from the screen appearing.
    static let firstCheer = 0.25
    static let cheerStagger = 0.04
    static let checkInsStart = 1.9
    static let stillCheckInsStart = 0.6
    static let checkInStagger = 0.35
    static let firstChange = 6.0
    static let interval = 4.0
    /// The slogan rises in this long after the break, and the button this long after it.
    static let revealDelay = 0.2
    static let buttonDelay = 0.08
    /// How many looks the crowd changes between.
    static let looks = 8
    /// The canvas is 240 by 320; its feet stand at 96% of its height.
    static let aspect = 320.0 / 240.0
    static let feetInCanvas = 0.957
    /// The word's line, 60 points tall, starts this far below the top of the screen's free area
    /// (101 on a 390 by 844 phone), and the slogan's under it.
    static let titleTop = 54.0
    static let wordLine = 60.0
    /// The floor's top, in design points above the bottom of the free area: above the back row.
    static let floorAbove = 172.0

    private(set) var players: [CharacterPlayer?] = Array(repeating: nil, count: 5)
    /// Bumped on every change, so the new look pops in.
    private(set) var versions = Array(repeating: 0, count: 5)
    private(set) var taps = Array(repeating: 0, count: 5)
    private(set) var middleLook: Outfit?
    /// Who is napping for their 请假条 now, and since when, for the z over their head.
    private(set) var dozing = Array(repeating: false, count: 5)
    private(set) var dozedAt = Array(repeating: Date.distantPast, count: 5)
    @ObservationIgnored private var pool: [Member] = []
    /// Which of `pool` each spot shows.
    @ObservationIgnored private var shown: [Int] = []
    /// Spots in the middle of a check-in, which a timed change of look passes over.
    @ObservationIgnored private var busy: Set<Int> = []
    @ObservationIgnored private var still = false
    @ObservationIgnored private var script: [Task<Void, Never>] = []
    @ObservationIgnored private var tick = 0

    /// Builds the looks off the main actor and shows five.
    func load(reduceMotion: Bool) async {
        guard pool.isEmpty, let catalog = try? Catalog.placeholder() else { return }
        still = reduceMotion
        var generator = SystemRandomNumberGenerator()
        var looks: [Outfit] = []
        while looks.count < Self.looks {
            // What a draft of it wears: an animal leaves out a person's hair and face.
            let look = CharacterDraft(
                catalog: catalog, look: CharacterDraft.randomLook(from: catalog, using: &generator),
                persona: .energetic, nickname: ""
            ).outfit
            if !looks.contains(look) { looks.append(look) }
        }
        var built: [Member] = []
        for look in looks {
            let persona = Persona.allCases.randomElement(using: &generator) ?? .energetic
            guard let figure = try? await CastMember.figure(wearing: look),
                let idle = reduceMotion ? Clip.still : try? PlaceholderCharacter.clip("idle", persona: persona),
                let player = try? CharacterPlayer(figure: figure, idle: idle)
            else { continue }
            built.append(Member(outfit: look, persona: persona, figure: figure, idle: idle, player: player))
        }
        guard pool.isEmpty, built.count >= spots.count else { return }
        pool = built
        shown = Array(0..<spots.count)
        players = shown.map { pool[$0].player }
        middleLook = pool[shown[Self.middle]].outfit
    }

    /// From the break (`sprinting`) or from the still screen appearing: the cheer (after a
    /// sprint only), a check-in each, then a change of look every `interval`. Reduce Motion
    /// keeps everyone still and only changes looks.
    func play(sprinting: Bool) {
        guard script.isEmpty, !pool.isEmpty else { return }
        let start = ContinuousClock.now
        func at(_ seconds: Double, _ action: @escaping @MainActor (WelcomeCrowd) async -> Void) {
            script.append(
                Task { [weak self] in
                    try? await Task.sleep(until: start + .seconds(seconds), clock: .continuous)
                    guard let self, !Task.isCancelled else { return }
                    await action(self)
                })
        }
        if !still {
            let checkIns = sprinting ? Self.checkInsStart : Self.stillCheckInsStart
            for (rank, index) in Self.cheerOrder.enumerated() {
                if sprinting { at(Self.firstCheer + Self.cheerStagger * Double(rank)) { $0.cheer(index) } }
                at(checkIns + Self.checkInStagger * Double(rank)) { await $0.checkIn(index) }
            }
        }
        at(Self.firstChange) { crowd in
            while !Task.isCancelled {
                crowd.changeNext()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func stop() {
        script.forEach { $0.cancel() }
        script = []
    }

    /// A tap: this one changes now, and plays its pick.
    func swap(_ index: Int) {
        taps[index] += 1
        change(index)
    }

    private func cheer(_ index: Int) {
        let member = pool[shown[index]]
        guard let clip = try? PlaceholderCharacter.clip("cheer", persona: member.persona) else { return }
        try? member.player.play(clip)
    }

    /// Holds what the move needs, plays it once, then puts it down and goes back to idle.
    private func checkIn(_ index: Int) async {
        let move = spots[index].checkIn
        let member = pool[shown[index]]
        guard
            let figure = try? await CastMember.figure(wearing: PlaceholderCharacter.dressed(member.outfit, for: move)),
            let clip = try? PlaceholderCharacter.clip(for: move, persona: member.persona),
            pool[shown[index]].player === member.player
        else { return }
        busy.insert(index)
        defer { busy.remove(index) }
        try? member.player.wear(figure, idle: member.idle)
        try? member.player.play(clip)
        if move == .excuse { (dozing[index], dozedAt[index]) = (true, .now) }
        try? await Task.sleep(for: .seconds(clip.duration + 0.15))
        dozing[index] = false
        try? member.player.wear(member.figure, idle: member.idle)
    }

    /// The next in `order` that isn't mid check-in changes.
    private func changeNext() {
        for _ in Self.order.indices {
            let index = Self.order[tick % Self.order.count]
            tick += 1
            if !busy.contains(index) {
                change(index)
                return
            }
        }
    }

    /// Changes one spot into a look no other spot is showing.
    private func change(_ index: Int) {
        let free = pool.indices.filter { !shown.contains($0) }
        guard let next = free.randomElement() else { return }
        shown[index] = next
        players[index] = pool[next].player
        versions[index] += 1
        dozing[index] = false
        if index == Self.middle { middleLook = pool[next].outfit }
    }
}
#endif
