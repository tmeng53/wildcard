#if os(iOS)
import AvatarArt
import AvatarUI
import CheckInDomain
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
            OpeningsPlayed.played(takeover, now: now())
            return
        }
        await land(on: scene, move: move)
    }

    /// Whether a takeover's opening covers the screen, until its 进场.
    public var isShowingOpening: Bool { opening != nil }

    /// Everyone in the opening: teammates either side of me, as the home stands them.
    var openingSquad: [CharacterPlayer] {
        let mates = cast.mates.map(\.player)
        let half = mates.count / 2
        return Array(mates.prefix(half)) + (player.map { [$0] } ?? []) + Array(mates.dropFirst(half))
    }

    /// The opening has played: the squad cheers where it stands.
    func cheerInOpening() {
        for mate in cast.mates {
            if let cheer = try? PlaceholderCharacter.clip("cheer", persona: mate.persona, species: mate.species) {
                try? mate.player.play(cheer)
            }
        }
        if let cheer = try? PlaceholderCharacter.clip(
            "cheer", persona: myPersona, species: PlaceholderCharacter.species(of: myLook))
        {
            try? player?.play(cheer)
        }
    }

    /// 进场: the opening lifts and the squad drops onto the scene.
    func enterFromOpening() {
        opening = nil
        Task { await dropIn(on: scene, coveredAt: .now) }
    }
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
