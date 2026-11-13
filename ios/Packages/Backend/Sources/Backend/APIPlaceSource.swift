import APIContract
import Contracts
import DesignSystem
import FeedDomain
import Foundation
import PlacesDomain

/// A place's page over our API (`GET /squads/{squadId}/places/{key}`): what the squad did there,
/// counted by the server from the posts tagged with it, with the authors' characters from the
/// squad's today and each cover kept on the phone or else from the URL the server signed.
public struct APIPlaceSource: PlaceSource {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func detail(of place: PlaceKey, in squad: SquadID) async throws(PlacesError) -> PlaceDetail? {
        do throws(APIError) {
            let wire = try await api.call {
                try await api.client.getSquadPlace(path: .init(squadId: squad.description, key: place.rawValue))
                    .ok.body.json
            }
            return try api.read { () throws(ContractsError) in try PlaceDetail(wire) }
        } catch .refused(.placeNotFound) {
            return nil
        } catch {
            throw PlacesError(error)
        }
    }

    public func characters(in squad: SquadID) async throws(PlacesError) -> [MemberID: MemberCharacter] {
        do throws(APIError) {
            let today = try await api.today(of: squad)
            var characters: [MemberID: MemberCharacter] = [:]
            for mate in today.members {
                characters[mate.member] = mate.character
            }
            return characters
        } catch {
            throw PlacesError(error)
        }
    }

    public func photo(_ ref: PhotoRef) async -> Data? {
        await api.photo(ref)
    }
}

extension PlaceDetail {
    /// The page as the API sends it; a post this build can't read (a sport it doesn't know yet)
    /// is left off the page, never the page itself.
    init(_ wire: Components.Schemas.PlaceDetail) throws(ContractsError) {
        let meals = wire.meals
        self.init(
            place: try Place(wire.place), visits: wire.visits, people: wire.people, stars: wire.stars,
            sports: wire.sports.compactMap { sport in
                (try? Activity(sport)).map { SportCount($0, count: sport.count) }
            },
            meals: MealTally(
                healthyMeals: meals.healthyMeal, cheatMeals: meals.cheatMeal, healthy: meals.healthy,
                tasty: meals.tasty, calorieValue: meals.calorieValue),
            posts: wire.posts.compactMap { try? PlaceVisit($0) })
    }
}

extension PlaceVisit {
    init(_ wire: Components.Schemas.PlaceVisit) throws(ContractsError) {
        guard let id = UUID(uuidString: wire.checkIn), let author = UUID(uuidString: wire.member) else {
            throw .invalidID(wire.checkIn)
        }
        let kind: CheckInKind =
            switch wire.kind {
            case .trained: .trained
            case .healthyMeal: .healthyMeal
            case .cheatMeal: .cheatMeal
            }
        let score: VisitScore? =
            if let stars = wire.stars { .stars(stars) } else { wire.calorieValue.map(VisitScore.calorieValue) }
        var cover: PhotoRef?
        if let photo = wire.cover { cover = try PhotoRef(photo.value1) }
        self.init(
            id: CheckInID(id), author: MemberID(author), kind: kind, activity: try Activity(wire),
            day: try LocalDay(wire.day), cover: cover, minutes: wire.minutes, score: score)
    }
}

extension PlacesError {
    /// What a failed API call means for a place's page.
    init(_ error: APIError) {
        self =
            switch error {
            case .account(.signedOut), .account(.credentialRejected), .account(.canceled): .signedOut
            case .refused(.squadNotJoined): .notInSquad
            default: .unavailable
            }
    }
}
