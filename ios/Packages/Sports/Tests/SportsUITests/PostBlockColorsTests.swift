import Contracts
import DesignSystem
import SportsUI
import Testing

private let names = CatalogNames(simplifiedChinese: "冬季", english: "Winter", traditionalChinese: "冬季")

struct PostBlockColorsTests {
    @Test func aTrainingWearsItsSportCategorysColour() {
        let catalog = SportCatalog(
            categories: [
                SportCatalog.Category(
                    id: "winter", names: names, color: "#2F86C4",
                    entries: [
                        SportCatalog.Entry(
                            sport: "ski", names: names, icon: "figure.skiing.downhill", offered: true,
                            category: "winter")
                    ])
            ], signUpCommon: [], checkInQuick: [])
        let colors = PostBlockColors(kind: .trained, activity: .sport("ski"), in: catalog)
        #expect(colors.fill.hex == "#2F86C4")
        #expect(colors.ink.hex == "#FFFFFF")
        #expect(colors.shade.hex == "#276EA1")
    }

    @Test func aSportTheListDoesNotHaveWearsTheGymsSteel() {
        #expect(PostBlockColors(kind: .trained, activity: .sport("quidditch"), in: .empty).fill.hex == "#4A6C8C")
        #expect(PostBlockColors(kind: .trained, activity: nil, in: .empty).fill.hex == "#4A6C8C")
    }

    /// Meals keep their scenes' accents, and no block is the brand's graphite: a run of 请假条
    /// made 我的动态 a wall of black squares (Tracy, 2026-11-08).
    @Test func otherKindsWearTheirScenesAndNeverGraphite() {
        #expect(PostBlockColors(kind: .healthyMeal, activity: nil).fill.hex == "#4F6B22")
        #expect(PostBlockColors(kind: .cheatMeal, activity: nil).fill.hex == "#E65345")
        #expect(PostBlockColors(kind: .disclaimer, activity: nil).fill.hex == "#4A6C8C")
    }
}
