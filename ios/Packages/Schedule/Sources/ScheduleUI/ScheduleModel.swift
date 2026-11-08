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
    /// The member's character in the poster's corner, training at today's sport (today's 练了,
    /// else today's plan) in its kit, or at the squad's scene's sport on a day with neither.
    private(set) var player: CharacterPlayer?
    /// The look `player` wears: the stand-in until the profile brings the member's own.
    private var look: CharacterLook?
    /// The squad's scene, whose sport `player` trains at when today has none.
    private var scene = SceneTheme.gym
    /// Today's sport `player` trains at, as last made.
    private var training: Activity?
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

    /// The look in today's sport's kit (else the scene's), looping its move; cheering as worn if
    /// the kit can't be read.
    private func makePlayer() {
        let outfit = look.map { Outfit($0) } ?? PlaceholderCharacter.lifter
        let persona = look.map { Persona($0) } ?? .energetic
        training = store.todaysActivity
        let activity = training ?? .sport(scene.sport)
        if let kitLoop = try? PlaceholderCharacter.trainingLoop(
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
    /// puts it to today's sport when that changed.
    private func dressPlayer() {
        let mine = store.profile?.look
        guard (mine != nil && mine != look) || store.todaysActivity != training else { return }
        if let mine { look = mine }
        makePlayer()
    }

    /// Puts the character to today's sport, when it changed.
    func followToday() {
        dressPlayer()
    }

    /// Puts the character to the squad's scene's sport, once the screen knows the scene.
    func train(on scene: SceneTheme) {
        guard scene != self.scene else { return }
        self.scene = scene
        makePlayer()
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
        fuelOpen = false
        writingFuel = false
        Task { await store.show(week) }
    }

    /// Shows the 每周模板 instead of a week, from its chip.
    func showTemplate() {
        fuelOpen = false
        writingFuel = false
        Task { await store.showTemplate() }
    }

    /// 也改到模板: the week just changed becomes the template too.
    func copyToTemplate() {
        Task { await store.copyToTemplate() }
    }

    // MARK: The board

    func tap(_ day: Int) {
        fuelOpen = false
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
