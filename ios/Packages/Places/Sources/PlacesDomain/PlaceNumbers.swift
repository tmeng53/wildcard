import CheckInDomain
import Contracts

/// What a place's card shows under its name: 小队来过 and 来过的队友, then its rows, set by what
/// kind of place it is (Tracy, 2026-11-12): a gym or any place people train shows its 运动 rows, a
/// place people eat its 吃的 rows. Places have no score (Tracy, 2026-11-13). A place the squad
/// never tagged shows the same card with 0s.
public struct PlaceNumbers: Hashable, Sendable {
    public enum Face: Hashable, Sendable {
        case training
        case eating
    }

    /// One number on the card.
    public enum Cell: Hashable, Sendable {
        /// 小队来过 N 次.
        case visits(Int)
        /// 来过的队友 N 人.
        case people(Int)
    }

    /// One row under the numbers, its bar against the most-counted row.
    public enum Row: Hashable, Sendable {
        case sport(Activity, count: Int, fraction: Double)
        case healthyMeals(count: Int, fraction: Double)
        case cheatMeals(count: Int, fraction: Double)
    }

    public let face: Face
    public let cells: [Cell]
    public let rows: [Row]

    /// - Parameter detail: the squad's numbers there; nil for a place it never tagged.
    public init(kind: PlaceKind, detail: PlaceDetail?) {
        let meals = detail?.meals ?? .none
        let mealCount = meals.healthyMeals + meals.cheatMeals
        let face: Face =
            switch kind {
            case .food, .cafe, .market: .eating
            // A place Maps doesn't call a restaurant where the squad only ate.
            default: detail.map { $0.sports.isEmpty && mealCount > 0 } == true ? .eating : .training
            }
        self.face = face
        cells = [.visits(detail?.visits ?? 0), .people(detail?.people ?? 0)]
        switch face {
        case .training:
            let most = max(detail?.sports.map(\.count).max() ?? 1, 1)
            rows = (detail?.sports ?? []).filter { $0.count > 0 }.map {
                .sport($0.activity, count: $0.count, fraction: Double($0.count) / Double(most))
            }
        case .eating:
            let most = Double(max(meals.healthyMeals, meals.cheatMeals, 1))
            rows =
                (meals.healthyMeals > 0
                    ? [.healthyMeals(count: meals.healthyMeals, fraction: Double(meals.healthyMeals) / most)] : [])
                + (meals.cheatMeals > 0
                    ? [.cheatMeals(count: meals.cheatMeals, fraction: Double(meals.cheatMeals) / most)] : [])
        }
    }
}
