#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import Foundation

/// A takeover scene (a holiday's, which every squad's home shows that day) plays its opening the
/// first time this phone shows it each day: the art an admin uploaded at `openings/<scene id>/`,
/// the squad cheering in it, then 进场 drops the squad onto the scene. A scene with no opening
/// this build can read just shows.
extension TodayModel {
    /// Puts 今天 on `scene`, as `land(on:move:)` does, unless `takeover` names a scene whose
    /// opening hasn't played on this phone today: then the opening covers the screen first.
    public func land(on scene: SceneTheme, move: SceneMove?, takeover: String?) async {
        if let takeover, let loaded = OpeningsPlayed.unplayed(takeover, now: now()) {
            self.scene = scene
            opening = loaded
            standOpeningSquad()
            OpeningsPlayed.played(takeover, now: now())
            return
        }
        await land(on: scene, move: move)
    }

    /// Whether a takeover's opening covers the screen, until its 进场.
    public var isShowingOpening: Bool { opening != nil }

    /// Stands the squad for the opening's group photo: teammates either side of me, as the home
    /// stands them, each in the look they made and their persona's standing idle, whatever their
    /// day has them doing on the home. Someone already standing keeps their figure, so a 人浪
    /// under way carries on when the home reloads.
    func standOpeningSquad() {
        let mates = cast.mates.map { (member: Optional($0.id), look: $0.look, persona: $0.persona) }
        let half = mates.count / 2
        let myself: [(member: MemberID?, look: Outfit, persona: Persona)] =
            player == nil ? [] : [(member: nil, look: myLook, persona: myPersona)]
        openingFigures = (Array(mates.prefix(half)) + myself + Array(mates.dropFirst(half))).compactMap { wanted in
            if let standing = openingFigures.first(where: {
                $0.member == wanted.member && $0.look == wanted.look && $0.persona == wanted.persona
            }) {
                return standing
            }
            let species = PlaceholderCharacter.species(of: wanted.look)
            guard let figure = try? PlaceholderCharacter.figure(wearing: wanted.look),
                let idle = try? PlaceholderCharacter.clip("idle", persona: wanted.persona, species: species),
                let player = try? CharacterPlayer(figure: figure, idle: idle)
            else { return nil }
            return OpeningFigure(member: wanted.member, look: wanted.look, persona: wanted.persona, player: player)
        }
    }

    var openingSquad: [CharacterPlayer] { openingFigures.map(\.player) }

    /// The opening has played: the squad does the 人浪 across its group photo, each jumping a
    /// moment after the one on their left, as the home's 人浪 does, and again after a breath for
    /// as long as the opening shows, so it's there whenever the member looks.
    func cheerInOpening() {
        Task { @MainActor [weak self] in
            // 进场 ends it: the squad is dropping onto the scene.
            while let squad = self?.openingFigures, self?.opening != nil {
                let waves = squad.map { try? PlaceholderCharacter.clip(for: .wave, persona: $0.persona) }
                // Each jumps in turn, from the idle they stand in until then.
                for member in SquadPhoto.leftToRight(count: squad.count) {
                    guard self?.opening != nil else { return }
                    if let wave = waves[member] { try? squad[member].player.play(wave) }
                    try? await Task.sleep(for: .seconds(TogetherStage.waveStagger))
                }
                // The last one lands, then a breath.
                let longest = waves.compactMap(\.?.duration).max() ?? 0
                try? await Task.sleep(for: .seconds(longest + TodayModel.openingWaveBreath))
            }
        }
    }

    /// The pause between one 人浪 in the opening and the next, in seconds.
    static let openingWaveBreath = 1.5

    /// 进场: the opening lifts and the squad drops onto the scene.
    func enterFromOpening() {
        opening = nil
        openingFigures = []
        Task { await dropIn(on: scene, coveredAt: .now) }
    }
}

/// One of the squad standing in an opening's group photo: who (nil for me), what they wear and
/// how they move, and the figure made for the photo.
struct OpeningFigure {
    let member: MemberID?
    let look: Outfit
    let persona: Persona
    let player: CharacterPlayer
}

/// Which takeover openings this phone played, and on which day, so each plays once a day.
enum OpeningsPlayed {
    private static func key(_ scene: String) -> String { "opening.played." + scene }

    private static func day(_ now: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// The opening of `scene`, unless it already played today or this build can't read it.
    static func unplayed(_ scene: String, now: Date) -> OpeningArt.Loaded? {
        guard UserDefaults.standard.string(forKey: key(scene)) != day(now) else { return nil }
        return OpeningArt.load(scene)
    }

    static func played(_ scene: String, now: Date) {
        UserDefaults.standard.set(day(now), forKey: key(scene))
    }
}
#endif
