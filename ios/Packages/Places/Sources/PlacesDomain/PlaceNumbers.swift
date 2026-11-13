import CheckInDomain
import Contracts

/// What a place's card shows under its name: its numbers, then its rows, set by what kind of
/// place it is (Tracy, 2026-11-12). A gym or any place people train shows 小队评分, 小队来过 and
/// 来过的队友 over its 运动 rows; a place people eat shows 健康, 好吃, 卡价比 and 小队来过 over its
/// 吃的 rows. A place the squad never tagged shows the same card with nothing in it: 「—」 and 0.
public struct PlaceNumbers: Hashable, Sendable {
    public enum Face: Hashable, Sendable {
        case training
        case eating
    }

    /// One number on the card.
    public enum Cell: Hashable, Sendable {
        /// 小队评分, stars; nil before anyone gave one.
        case squadScore(Double?)
        /// 健康, stars.
        case healthy(Double?)
        /// 好吃, stars.
        case tasty(Double?)
        /// 卡价比, a plain number.
        case calorieValue(Double?)
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
        switch face {
        case .training:
            cells = [.squadScore(detail?.stars), .visits(detail?.visits ?? 0), .people(detail?.people ?? 0)]
            let most = max(detail?.sports.map(\.count).max() ?? 1, 1)
            rows = (detail?.sports ?? []).filter { $0.count > 0 }.map {
                .sport($0.activity, count: $0.count, fraction: Double($0.count) / Double(most))
            }
        case .eating:
            // 卡价比 once the squad was there; an empty card keeps to three.
            cells =
                [.healthy(meals.healthy), .tasty(meals.tasty)]
                + (detail == nil ? [] : [.calorieValue(meals.calorieValue)]) + [.visits(detail?.visits ?? 0)]
            let most = Double(max(meals.healthyMeals, meals.cheatMeals, 1))
            rows =
                (meals.healthyMeals > 0
                    ? [.healthyMeals(count: meals.healthyMeals, fraction: Double(meals.healthyMeals) / most)] : [])
                + (meals.cheatMeals > 0
                    ? [.cheatMeals(count: meals.cheatMeals, fraction: Double(meals.cheatMeals) / most)] : [])
        }
    }
}

/// How a score reads: a member's own stars as a whole number (5), an average or a 卡价比 to one
/// decimal (4.0), 「—」 before there is one.
public enum ScoreText {
    public static let none = "—"

    public static func average(_ value: Double?) -> String {
        guard let value, value.isFinite else { return none }
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(abs(tenths % 10))"
    }

    public static func visit(_ score: VisitScore) -> String {
        switch score {
        case .stars(let stars): String(stars)
        case .calorieValue(let value): average(value)
        }
    }
}
