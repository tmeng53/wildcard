import Contracts
import DesignSystem

/// A post block's colours, which a 训练's 成绩条, route and chart wear too: a 练了 takes its sport
/// category's colour (data in the sports list, Tracy 2026-11-08), a meal the accent of its kind's
/// scene, and a 请假条 the gym's steel, never the brand's graphite (Tracy, 2026-11-08). White on
/// all of them.
public struct PostBlockColors: Sendable, Hashable {
    public let fill: SRGBColor
    public let ink: SRGBColor
    /// The fill darker, for a pattern or line on it.
    public let shade: SRGBColor

    /// `catalog` is the sports list whose category colours a 练了 takes, the app's by default.
    public init(kind: CheckInKind, activity: Activity?, in catalog: SportCatalog = SportList.shared.catalog) {
        switch kind {
        case .trained:
            guard case .sport(let sport) = activity else {
                // A sport people name themselves wears the gym's steel.
                self.init(BlockColors(hex: nil))
                return
            }
            // A sport this build's list doesn't have yet wears the gym's steel too.
            self.init(BlockColors(hex: catalog.color(of: sport)))
        case .healthyMeal: self.init(BlockColors(scene: .tennis))
        case .cheatMeal: self.init(BlockColors(scene: .track))
        case .disclaimer: self.init(BlockColors(scene: .gym))
        }
    }

    /// A check-in's colours.
    public init(checkIn: CheckIn) {
        switch checkIn.entry {
        case .trained(let training): self.init(kind: .trained, activity: training.activity)
        case .healthyMeal: self.init(kind: .healthyMeal, activity: nil)
        case .cheatMeal: self.init(kind: .cheatMeal, activity: nil)
        case .disclaimer: self.init(kind: .disclaimer, activity: nil)
        }
    }

    private init(_ colors: BlockColors) {
        (fill, ink, shade) = (colors.fill, colors.ink, colors.shade)
    }
}
