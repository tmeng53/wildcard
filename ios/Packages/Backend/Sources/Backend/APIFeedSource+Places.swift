import APIContract
import Contracts
import FeedDomain
import Foundation

// A tagged place's page (地点页) and the member's score for it, over
// `GET /squads/{squadId}/places/{key}` and `PUT /me/place-ratings/{key}`.
extension APIFeedSource: PlaceBook {
    public func page(of key: PlaceKey, in squad: SquadID) async throws(FeedError) -> PlacePage? {
        let wire: Components.Schemas.PlaceDetail
        do throws(APIError) {
            wire = try await api.call {
                try await api.client.getSquadPlace(path: .init(squadId: squad.description, key: key.rawValue)).ok
                    .body.json
            }
        } catch {
            if error == .refused(.placeNotFound) { return nil }
            throw FeedError(error)
        }
        guard let page = PlacePage(wire, key: key) else { throw .refused }
        return page
    }

    public func rate(_ key: PlaceKey, stars: Int) async throws(FeedError) {
        do throws(APIError) {
            _ = try await api.call {
                try await api.client.ratePlace(
                    path: .init(key: key.rawValue), body: .json(.init(version: ._1, stars: stars))
                ).ok
            }
        } catch {
            throw FeedError(error)
        }
    }
}

extension PlacePage {
    /// The page as the API sends it; nil when its place can't be read. A post or a sport this
    /// build can't read is left out, never the page.
    init?(_ wire: Components.Schemas.PlaceDetail, key: PlaceKey) {
        let spot = wire.place
        guard
            let place = try? Place(
                name: spot.name, appleID: spot.appleId, category: spot.category, latitude: spot.latitude,
                longitude: spot.longitude)
        else { return nil }
        self.init(
            key: key, place: place, visits: wire.visits, people: wire.people, stars: wire.stars, raters: wire.raters,
            myStars: wire.myStars,
            sports: wire.sports.compactMap { entry in
                Self.activity(sport: entry.sport, custom: entry.customSport).map {
                    SportCount(activity: $0, count: entry.count)
                }
            },
            meals: Meals(
                healthyMeals: wire.meals.healthyMeal, cheatMeals: wire.meals.cheatMeal, healthy: wire.meals.healthy,
                tasty: wire.meals.tasty, calorieValue: wire.meals.calorieValue),
            posts: wire.posts.compactMap(PlaceVisit.init))
    }

    /// A sport as the API names it: a listed sport's id, or `custom` with the name people gave.
    static func activity(sport: String?, custom: String?) -> Activity? {
        if sport == "custom" { return custom.flatMap { try? CustomSport($0) }.map(Activity.custom) }
        return sport.flatMap(Sport.init(rawValue:)).map(Activity.sport)
    }
}

extension PlaceVisit {
    init?(_ wire: Components.Schemas.PlaceVisit) {
        guard let checkIn = UUID(uuidString: wire.checkIn), let member = UUID(uuidString: wire.member),
            let day = try? LocalDay(wire.day)
        else { return nil }
        let kind: Kind =
            switch wire.kind {
            case .trained: .trained(PlacePage.activity(sport: wire.sport, custom: wire.customSport))
            case .healthyMeal: .healthyMeal
            case .cheatMeal: .cheatMeal
            }
        self.init(
            checkIn: CheckInID(checkIn), member: MemberID(member), kind: kind, minutes: wire.minutes, day: day,
            createdAt: Timestamp(wire.createdAt))
    }
}
