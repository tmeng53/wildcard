#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Foundation
import SportsUI

/// What my character has on and loops on the scene.
struct Worn: Equatable {
    let outfit: Outfit
    let idle: String
}

extension TodayModel {
    /// The sports' kits, read once.
    private static let kits = try? PlaceholderCharacter.sportKits()

    /// What I wear and loop on the scene: once I 练了 a sport today, its kit and its move, from the
    /// same `kits.json` and `move(for:)` as sign-up's 平时练什么 and the week card; else my own
    /// look and my persona's idle.
    private var dress: (outfit: Outfit, idle: Clip)? {
        if let home, let activity = home.todaysSport(of: home.member), let kits = Self.kits {
            let kit = kits.kit(for: activity, in: SportList.shared.catalog)
            if let move = try? PlaceholderCharacter.move(for: kit, persona: myPersona) {
                return (kit.dress(myLook), move)
            }
        }
        guard
            let idle = try? PlaceholderCharacter.clip(
                "idle", persona: myPersona, species: PlaceholderCharacter.species(of: myLook))
        else { return nil }
        return (myLook, idle)
    }

    /// Dresses my character for the day, when that changed: with the kit's hop when it changes
    /// as I watch (after a 练了), else at once.
    func dressMe(hop: Bool) {
        guard let dress else { return }
        let next = Worn(outfit: dress.outfit, idle: dress.idle.name)
        guard next != worn || player == nil,
            let figure = try? PlaceholderCharacter.figure(wearing: dress.outfit)
        else { return }
        // What it wears counts only once it is on, so a failed change is tried again next time.
        guard let player else {
            player = try? CharacterPlayer(figure: figure, idle: dress.idle)
            if player != nil { worn = next }
            return
        }
        if hop, let kitHop = try? PlaceholderCharacter.kitHop(),
            (try? player.change(into: figure, idle: dress.idle, hop: kitHop)) != nil
        {
            hopEnds = Date.now.addingTimeInterval(kitHop.out.duration + kitHop.in.duration)
            worn = next
        } else if (try? player.wear(figure, idle: dress.idle)) != nil {
            worn = next
        }
    }

    /// Whether my character is hopping into its kit: a clip played now would stop the change
    /// halfway, in the clothes on screen.
    var isChanging: Bool {
        hopEnds.map { Date.now < $0 } ?? false
    }

    /// I tapped my own character: it plays its signature move once, the move of the prop it
    /// holds (the kit's, once I trained today), or its cheer. Not while a pat, a 练了's cheer, a
    /// hop into the kit or the squad's drop plays.
    func tapMe() {
        guard pats.pat == nil, arrival == nil, !holdsDress, !isChanging, let player else { return }
        guard
            let move = try? PlaceholderCharacter.signatureMove(
                wearing: worn?.outfit ?? myLook, persona: myPersona)
        else { return }
        try? player.play(move)
    }
}
#endif
