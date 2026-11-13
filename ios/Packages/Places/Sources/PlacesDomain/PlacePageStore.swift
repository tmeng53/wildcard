import CheckInDomain
import Contracts
import Foundation
import Observation

/// A place's page as the app reads it: the place itself, drawn at once from what opened it, then
/// what Maps says of it and the squad's numbers and posts there, read side by side.
@MainActor @Observable
public final class PlacePageStore {
    /// Where reading the squad's numbers stands.
    public enum Phase: Equatable, Sendable {
        case loading
        /// Read; `detail` is nil for a place the squad never tagged, or one without a key.
        case loaded
        /// The server couldn't be reached; the card shows the place alone until a pull reads it
        /// again.
        case offline
        /// The member isn't in the squad any more.
        case notInSquad
        /// The member is signed out.
        case signedOut
    }

    public let place: Place
    public private(set) var phase = Phase.loading
    public private(set) var detail: PlaceDetail?
    public private(set) var facts: PlaceFacts?
    /// The squad's members' characters as last read: the posts' authors' names and heads.
    public private(set) var characters: [MemberID: MemberCharacter] = [:]

    private let squad: SquadID?
    private let source: any PlaceSource
    private let directory: any PlaceDirectory

    /// - Parameter squad: the reader's squad; nil when they are in none, whose page is the card
    ///   alone.
    public init(place: Place, squad: SquadID?, source: any PlaceSource, directory: any PlaceDirectory) {
        (self.place, self.squad, self.source, self.directory) = (place, squad, source, directory)
    }

    /// What kind of place it is, from Maps' category.
    public var kind: PlaceKind { place.kind }

    /// The card's numbers and rows.
    public var numbers: PlaceNumbers { PlaceNumbers(kind: kind, detail: detail) }

    /// Whether the card shows the squad's numbers, rows and posts: not while they couldn't be
    /// read, so a failed read never shows as a place the squad never went to.
    public var showsSquad: Bool { phase == .loading || phase == .loaded }

    /// The posts there, newest first.
    public var posts: [PlaceVisit] { detail?.posts ?? [] }

    /// Reads Maps and the squad's numbers side by side; the card is up before either answers.
    public func load() async {
        async let maps = directory.facts(for: place)
        await loadSquad()
        if let found = await maps { facts = found }
    }

    /// A post's photo, as JPEG.
    public func photo(_ ref: PhotoRef) async -> Data? { await source.photo(ref) }

    private func loadSquad() async {
        guard let squad, let key = place.key else {
            phase = .loaded
            return
        }
        do throws(PlacesError) {
            async let people = source.characters(in: squad)
            detail = try await source.detail(of: key, in: squad)
            characters = (try? await people) ?? characters
            phase = .loaded
        } catch {
            phase =
                switch error {
                case .signedOut: .signedOut
                case .notInSquad: .notInSquad
                case .unavailable: .offline
                }
        }
    }
}
