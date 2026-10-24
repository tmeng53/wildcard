#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import Foundation
import Observation
import ScheduleDomain

/// The 出赛表 screen's state over its store: what is open under the poster, the title whose
/// award line shows, the member's character on the poster and saving the poster to Photos.
@MainActor @Observable
public final class ScheduleModel {
    /// What shows under the poster.
    public enum Panel: Equatable {
        /// The lifetime and squad counts, or next week's countdown.
        case counts
        /// The picks for the selected day.
        case dayPicks(Int)
        /// Next week's 饮食小目标.
        case fuel
    }

    /// Where saving the poster to Photos stands.
    public enum Saving: Equatable {
        case idle
        case working
        case saved
        /// The member hasn't let the app add to Photos.
        case notAllowed
        case failed
    }

    public let store: ScheduleStore
    /// The member's character, cheering in the poster's corner.
    private(set) var player: CharacterPlayer?
    /// The look `player` wears: the stand-in until the profile brings the member's own.
    private var look: CharacterLook?
    private(set) var fuelOpen = false
    /// Typing a 饮食小目标 of their own.
    var writingFuel = false
    private(set) var saving = Saving.idle

    private let photos: any PosterSaver

    public init(store: ScheduleStore, photos: any PosterSaver = PhotoLibrarySaver()) {
        self.store = store
        self.photos = photos
        player = Self.player(wearing: PlaceholderCharacter.lifter, persona: .energetic)
    }

    private static func player(wearing outfit: Outfit, persona: Persona) -> CharacterPlayer? {
        try? CharacterPlayer(
            figure: PlaceholderCharacter.figure(wearing: outfit),
            idle: PlaceholderCharacter.clip(
                "cheer", persona: persona, species: PlaceholderCharacter.species(of: outfit)))
    }

    /// Dresses the poster's character in the member's own look once the profile has one.
    private func dressPlayer() {
        guard let mine = store.profile?.look, mine != look else { return }
        look = mine
        player = Self.player(wearing: Outfit(mine), persona: Persona(mine))
    }

    var panel: Panel {
        if fuelOpen, store.canEditFuel { return .fuel }
        if case .selected(let index) = store.board?.focus { return .dayPicks(index) }
        return .counts
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

    /// Saves the poster, drawn by `render`, to Photos.
    func savePoster(_ render: () -> PosterImage?) async {
        guard saving != .working else { return }
        saving = .working
        guard let image = render() else {
            saving = .failed
            return
        }
        saving = await photos.save(image)
    }

    /// Lets go of the saved or failed note.
    func clearSaving() {
        if saving != .working { saving = .idle }
    }
}
#endif
