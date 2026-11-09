#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import Foundation
import Observation
import ScheduleDomain
import SportsUI

/// The 出赛表 screen's state over its store: what is open under the poster, the title whose
/// award line shows, the member's character on the poster and saving the poster to Photos.
@MainActor @Observable
public final class ScheduleModel {
    /// What shows under the poster.
    public enum Panel: Equatable {
        /// Next week's countdown or a past week's awards; nothing under this week.
        case weekNote
        /// The picks for the selected day.
        case dayPicks(Int)
        /// Next week's 饮食小目标.
        case fuel
    }

    /// Where 存图 stands: drawing the poster, then sharing the picture (the poster flashes as a
    /// screenshot does and 存图's sheet opens on it, to save or share), or a picture that couldn't
    /// be drawn.
    public enum Saving: Equatable {
        case idle
        case working
        case sharing(SharedPoster)
        case failed
    }

    /// A drawn poster on its way to 存图's sheet; each 存图 is a new one.
    public struct SharedPoster: Identifiable, Equatable {
        public let id: Int
        public let image: PosterImage

        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    public let store: ScheduleStore
    /// What the poster's character does.
    enum Play: Equatable {
        case training(Activity)
        /// Sitting down, as on the home on a rest day.
        case resting
    }

    /// The member's character in the poster's corner, doing `play` in its kit.
    private(set) var player: CharacterPlayer?
    /// The day of the shown week (Monday 0) the member last tapped, whose sport the character
    /// plays, past days too; nil plays today's. Another week or the 我的每周计划 starts again from
    /// today.
    private(set) var watchedDay: Int?
    /// The look `player` wears: the stand-in until the profile brings the member's own.
    private var look: CharacterLook?
    /// The squad's scene, whose sport `player` trains at when today has none.
    private var scene = SceneTheme.gym
    /// What `player` was made to do.
    private var played: Play?
    /// What `player` was made from, for drawing its key pose when the poster is saved.
    private var loop: (figure: Figure, clip: Clip)?
    private(set) var fuelOpen = false
    /// Typing a 饮食小目标 of their own.
    var writingFuel = false
    private(set) var saving = Saving.idle
    private var shares = 0

    /// How long 只改了这一周 · 也改到模板 stays after a week's change before it goes by itself.
    let templateOfferHold: Duration

    /// `templateOfferHold`: longer only where UI tests need time to find the offer.
    public init(store: ScheduleStore, templateOfferHold: Duration = .seconds(5)) {
        self.store = store
        self.templateOfferHold = templateOfferHold
        makePlayer()
    }

    /// What the character does now: the tapped day's sport, sitting down on a tapped rest day;
    /// with no day tapped, today's sport (today's 练了, else today's plan), or the squad's scene's
    /// on a day with neither.
    var play: Play {
        if let watchedDay {
            return store.shownActivity(on: watchedDay).map(Play.training) ?? .resting
        }
        return .training(store.todaysActivity ?? .sport(scene.sport))
    }

    /// The look doing `play`: in the sport's kit looping its move, or sitting as worn; cheering as
    /// worn if neither can be read.
    private func makePlayer() {
        let outfit = look.map { Outfit($0) } ?? PlaceholderCharacter.lifter
        let persona = look.map { Persona($0) } ?? .energetic
        let play = play
        played = play
        if case .resting = play, let sitting = try? PlaceholderCharacter.sitting(persona: persona),
            let figure = try? PlaceholderCharacter.figure(wearing: outfit),
            let player = try? CharacterPlayer(figure: figure, idle: sitting)
        {
            (self.player, loop) = (player, (figure, sitting))
            return
        }
        if case .training(let activity) = play,
            let kitLoop = try? PlaceholderCharacter.trainingLoop(
                for: activity, look: outfit, persona: persona, in: SportList.shared.catalog),
            let figure = try? PlaceholderCharacter.figure(wearing: kitLoop.outfit),
            let player = try? CharacterPlayer(figure: figure, idle: kitLoop.clip)
        {
            (self.player, loop) = (player, (figure, kitLoop.clip))
            return
        }
        loop = nil
        player = try? CharacterPlayer(
            figure: PlaceholderCharacter.figure(wearing: outfit),
            idle: PlaceholderCharacter.clip(
                "cheer", persona: persona, species: PlaceholderCharacter.species(of: outfit)))
    }

    /// Dresses the poster's character in the member's own look once the profile has one, and
    /// puts it to what it plays when that changed.
    private func dressPlayer() {
        let mine = store.profile?.look
        guard (mine != nil && mine != look) || play != played else { return }
        if let mine { look = mine }
        makePlayer()
    }

    /// Puts the character to what it plays, when that changed (a 练了 read in, a day's sport
    /// picked).
    func followPlay() {
        dressPlayer()
    }

    /// Puts the character to the squad's scene's sport, once the screen knows the scene.
    func train(on scene: SceneTheme) {
        guard scene != self.scene else { return }
        self.scene = scene
        dressPlayer()
    }

    /// The character as the saved poster shows it: holding its sport's signature pose, never
    /// whichever frame was on screen.
    var keyPose: (drawing: FigureDrawing, placements: [Placement])? {
        guard let loop else { return player?.restFrame }
        let start = Date(timeIntervalSinceReferenceDate: 0)
        guard let still = try? CharacterPlayer(figure: loop.figure, idle: loop.clip, now: start) else { return nil }
        let into = PlaceholderCharacter.keyPose(of: loop.clip) * loop.clip.duration
        return still.frame(at: start.addingTimeInterval(into))
    }

    var panel: Panel {
        if fuelOpen, store.canEditFuel { return .fuel }
        if case .selected(let index) = store.board?.focus { return .dayPicks(index) }
        return .weekNote
    }

    // MARK: Weeks

    func load() async {
        await store.load()
        dressPlayer()
    }

    func show(_ week: LocalDay) {
        watchedDay = nil
        fuelOpen = false
        writingFuel = false
        Task { await store.show(week) }
    }

    /// Shows the week to plan after a 战报 of the week before `week` (its 排下周): that week, or
    /// this week once it has begun, as a 战报 read late is planning the week it is in.
    public func plan(_ week: LocalDay) {
        show(store.today.map { max(week, $0.weekStart) } ?? week)
    }

    /// Shows the 我的每周计划 instead of a week, from its chip.
    func showTemplate() {
        watchedDay = nil
        fuelOpen = false
        writingFuel = false
        Task { await store.showTemplate() }
    }

    /// 也改到模板: the week just changed becomes the template too.
    func copyToTemplate() {
        Task { await store.copyToTemplate() }
    }

    // MARK: The board

    /// Puts the character to the day's sport, any day, and picks the day up where it can change.
    func tap(_ day: Int) {
        fuelOpen = false
        watchedDay = day
        dressPlayer()
        Task { await store.tap(day) }
    }

    func pick(_ activity: Activity) {
        Task { await store.pick(activity) }
    }

    func rest() {
        Task { await store.rest() }
    }

    // MARK: 饮食小目标

    func toggleFuelPanel() {
        guard store.canEditFuel else { return }
        store.release()
        fuelOpen.toggle()
        writingFuel = false
    }

    func toggle(_ goal: FuelGoal) {
        Task { await store.toggleFuel(goal) }
    }

    /// Adds the typed goal; false when it isn't one line of 1 to 8 characters.
    func addFuel(typed text: String) async -> Bool {
        do {
            try await store.addFuel(typed: text)
            writingFuel = false
            return true
        } catch {
            return false
        }
    }

    // MARK: Saving the poster

    /// Draws the poster with `render` and hands the picture to 存图's sheet.
    func sharePoster(_ render: () -> PosterImage?) {
        guard saving == .idle || saving == .failed else { return }
        saving = .working
        guard let image = render() else {
            saving = .failed
            return
        }
        shares += 1
        saving = .sharing(SharedPoster(id: shares, image: image))
    }

    /// 存图's sheet closed, or the failed note has been read.
    func clearSaving() {
        if saving != .working { saving = .idle }
    }
}
#endif
