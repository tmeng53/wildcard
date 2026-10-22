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
    let player: CharacterPlayer?
    private(set) var fuelOpen = false
    /// Typing a 饮食小目标 of their own.
    var writingFuel = false
    /// The title whose 颁奖词 shows over the poster.
    private(set) var openTitle: AwardTitle?
    private(set) var saving = Saving.idle
    /// Bumps each time the board answers a tap, for its haptic.
    private(set) var taps = 0
    private(set) var swaps = 0

    private let photos: any PosterSaver

    public init(store: ScheduleStore, photos: any PosterSaver = PhotoLibrarySaver()) {
        self.store = store
        self.photos = photos
        player = try? CharacterPlayer(
            figure: PlaceholderCharacter.figure(wearing: Self.look),
            idle: PlaceholderCharacter.clip("cheer", persona: Self.persona, species: Self.species))
    }

    /// The member's look and persona until they come with the profile, as on 今天.
    private static let look = PlaceholderCharacter.lifter
    private static let persona = Persona.energetic
    private static let species = "person"

    var panel: Panel {
        if fuelOpen, store.canEditFuel { return .fuel }
        if case .selected(let index) = store.board?.focus { return .dayPicks(index) }
        return .counts
    }

    // MARK: Weeks

    func load() async {
        await store.load()
    }

    func show(_ week: LocalDay) {
        fuelOpen = false
        writingFuel = false
        openTitle = nil
        Task { await store.show(week) }
    }

    // MARK: The board

    func tap(_ day: Int) {
        fuelOpen = false
        openTitle = nil
        Task {
            let outcome = await store.tap(day)
            switch outcome {
            case .locked: break
            case .swapped: swaps += 1
            case .selected, .lifted, .released: taps += 1
            }
        }
    }

    func pick(_ activity: Activity) {
        Task { await store.pick(activity) }
    }

    func rest() {
        Task { await store.rest() }
    }

    // MARK: Titles

    func toggle(_ title: AwardTitle) {
        openTitle = openTitle == title ? nil : title
        taps += 1
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
