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
    /// Me as the scene sees each of us: my day's status and, when my latest post today is a
    /// meal, what I'm eating.
    var myMember: StageMember? {
        guard let home else { return nil }
        return StageMember(
            id: home.member,
            status: StageStatus(
                training: store.myStatus, activity: home.todaysSport(of: home.member),
                plannedRest: home.mine?.plannedRest ?? false),
            firstCheckInAt: home.mine?.firstCheckInAt, keepsToTheBack: false, eating: home.todaysMeal(of: home.member))
    }

    /// What I'm doing on the scene, by the same rule as every teammate: training in my sport's
    /// kit, eating my latest meal, holding up my 请假条, sitting on a rest day, asleep at night
    /// until the lights go on, else standing.
    func myPose(at phase: DayPhase) -> StagePose? {
        myMember.map { cast.stage.pose(of: $0, at: phase) }
    }

    /// What I wear and loop on the scene in my pose (`StagePose.dress`, as each teammate): once
    /// I 练了 a sport today, its kit and its move, from the same `kits.json` and `move(for:)` as
    /// sign-up's 平时练什么 and the week card; my bowl or boba; else my own look and the pose's loop.
    private var dress: (outfit: Outfit, idle: Clip)? {
        let species = PlaceholderCharacter.species(of: myLook)
        if let pose = myPose(at: stagePhase), let home {
            if let dressed = try? pose.dress(
                myLook, trained: home.todaysSport(of: home.member), persona: myPersona, species: species)
            {
                return (dressed.outfit, dressed.loop)
            }
        }
        guard let idle = try? PlaceholderCharacter.clip("idle", persona: myPersona, species: species) else {
            return nil
        }
        return (myLook, idle)
    }

    /// New art came down while 今天 is up (a piece redrawn on the server): everyone on the scene is
    /// made again from it at once, as the next launch would, instead of keeping the parts drawn
    /// before. Waits for the squad's drop, after which they are placed anyway.
    public func artChanged() {
        guard home != nil, arrival == nil else { return }
        (player, worn) = (nil, nil)
        cast.forgetCharacters()
        placeSquad()
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

    /// I tapped my own character: my status shows over my head, as a teammate's does (睡着了
    /// while asleep), and it plays its signature move once, the move of the prop it holds (the
    /// kit's, once I trained today), or its cheer; asleep or eating, it keeps at it, as a
    /// teammate does. The move waits out a pat, a 练了's cheer, a hop into the kit or the squad's
    /// drop.
    func tapMe() {
        let pose = myPose(at: stagePhase)
        if let home, arrival == nil, pats.pat == nil { openTeammate(home.member) }
        switch pose {
        case .asleep?, .eating?: return
        case .standing?, .sitting?, .holdingSign?, .station?, .inPlace?, nil: break
        }
        guard pats.pat == nil, arrival == nil, !holdsDress, !isChanging, let player else { return }
        guard
            let move = try? PlaceholderCharacter.signatureMove(
                wearing: worn?.outfit ?? myLook, persona: myPersona)
        else { return }
        try? player.play(move)
    }

    /// The character whose head the card shows for a member (`MemberID`'s description).
    func head(of member: String) -> CharacterPlayer? {
        guard member != home?.member.description else { return player }
        return cast.mates.first { $0.id.description == member }?.player
    }
}
#endif
