import Contracts
import Foundation
import Observation

/// A place the member saved (收藏, Tracy 2026-11-12), with their own note; only they see it.
public struct SavedPlace: Hashable, Sendable, Identifiable {
    /// How many places a member keeps saved at once: the API's limit.
    public static let maxCount = 200

    public let key: PlaceKey
    public let place: Place
    public let note: SavedPlaceNote?
    /// When they first saved it since they last removed it; a new note keeps it.
    public let savedAt: Timestamp

    public var id: PlaceKey { key }

    public init(key: PlaceKey, place: Place, note: SavedPlaceNote?, savedAt: Timestamp) {
        (self.key, self.place, self.note, self.savedAt) = (key, place, note, savedAt)
    }
}

/// Why 收藏 couldn't be read or changed. Each case is something the caller can act on.
public enum SavedPlacesError: Error, Equatable, Sendable {
    /// Nobody is signed in any more.
    case signedOut
    /// The member keeps the most saved places already: one has to go first.
    case full
    /// The API or the network can't be reached; trying again later is safe.
    case unavailable
}

/// Where the member's saved places are kept: the API, for the signed-in member. `Backend` has
/// the adapter.
public protocol SavedPlaceSource: Sendable {
    /// Every place they saved, newest first.
    func list() async throws(SavedPlacesError) -> [SavedPlace]
    /// Saves the place, which has a key, or changes its note on one saved already; nil clears
    /// the note.
    func save(_ place: Place, note: SavedPlaceNote?) async throws(SavedPlacesError) -> SavedPlace
    /// Removes it; one not saved is fine too.
    func remove(_ key: PlaceKey) async throws(SavedPlacesError)
}

/// 收藏 as the app holds it: one for as long as the tabs are up, so the bookmark on a place's
/// page and the list on 我 always agree.
@MainActor @Observable
public final class SavedPlacesStore {
    public enum Phase: Equatable, Sendable {
        case loading
        case loaded
        /// The list couldn't be read; a pull reads it again.
        case failed
        case signedOut
    }

    public private(set) var phase = Phase.loading
    /// Newest saved first.
    public private(set) var places: [SavedPlace] = []
    /// A save or a removal from the note card is under way.
    public private(set) var isWriting = false

    private let source: any SavedPlaceSource
    private var hasLoaded = false

    public init(source: any SavedPlaceSource) {
        self.source = source
    }

    /// The place as saved, or nil when it isn't (or has no key, which can't be saved).
    public func saved(_ place: Place) -> SavedPlace? {
        guard let key = place.key else { return nil }
        return places.first { $0.key == key }
    }

    /// Reads the list the first time anything asks for it.
    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// Reads the list again.
    public func load() async {
        hasLoaded = true
        do throws(SavedPlacesError) {
            places = try await source.list()
            phase = .loaded
        } catch .signedOut {
            phase = .signedOut
        } catch {
            // A list read before stays up; a first read that failed is tried again next time.
            guard phase != .loaded else { return }
            (phase, hasLoaded) = (.failed, false)
        }
    }

    /// Saves the place with the note typed (blank for none), or changes the note on one saved
    /// already, which keeps its place in the list. Nil when it went through. Never before the list
    /// is read, so a note saved before can't be cleared by a card that never showed it.
    public func save(_ place: Place, note typed: String) async -> SavedPlacesError? {
        guard place.key != nil else { return .unavailable }
        let blank = typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let note = try? SavedPlaceNote(typed)
        guard blank || note != nil else { return .unavailable }
        if phase != .loaded { await load() }
        guard phase == .loaded else { return phase == .signedOut ? .signedOut : .unavailable }
        isWriting = true
        defer { isWriting = false }
        do throws(SavedPlacesError) {
            let saved = try await source.save(place, note: note)
            if let index = places.firstIndex(where: { $0.key == saved.key }) {
                places[index] = saved
            } else {
                places.insert(saved, at: 0)
            }
            return nil
        } catch {
            return error
        }
    }

    /// Takes the place off the list at once and puts it back where it was if the server says no.
    /// Nil when it went through.
    public func remove(_ key: PlaceKey) async -> SavedPlacesError? {
        guard let index = places.firstIndex(where: { $0.key == key }) else { return nil }
        let removed = places.remove(at: index)
        isWriting = true
        defer { isWriting = false }
        do throws(SavedPlacesError) {
            try await source.remove(key)
            return nil
        } catch {
            if !places.contains(where: { $0.key == key }) {
                places.insert(removed, at: min(index, places.count))
            }
            return error
        }
    }

    /// Whether a note typed so far can be saved: blank (no note) or a note the API takes.
    public static func canSave(note typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (try? SavedPlaceNote(typed)) != nil
    }
}

/// 收藏 kept on the phone for the sample squad, with the server's rules: a saved place keeps when
/// it was saved through a new note, and at most `SavedPlace.maxCount` are kept.
public actor InMemorySavedPlaceSource: SavedPlaceSource {
    private var places: [SavedPlace]
    private let now: @Sendable () -> Timestamp

    public init(places: [SavedPlace] = [], now: @escaping @Sendable () -> Timestamp) {
        (self.places, self.now) = (places, now)
    }

    public func list() async throws(SavedPlacesError) -> [SavedPlace] { places }

    public func save(_ place: Place, note: SavedPlaceNote?) async throws(SavedPlacesError) -> SavedPlace {
        guard let key = place.key else { throw .unavailable }
        if let index = places.firstIndex(where: { $0.key == key }) {
            let saved = SavedPlace(key: key, place: place, note: note, savedAt: places[index].savedAt)
            places[index] = saved
            return saved
        }
        guard places.count < SavedPlace.maxCount else { throw .full }
        let saved = SavedPlace(key: key, place: place, note: note, savedAt: now())
        places.insert(saved, at: 0)
        return saved
    }

    public func remove(_ key: PlaceKey) async throws(SavedPlacesError) {
        places.removeAll { $0.key == key }
    }
}
