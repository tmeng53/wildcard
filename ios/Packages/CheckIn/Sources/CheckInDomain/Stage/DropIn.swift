import DesignSystem
import Foundation

/// The squad dropping onto home once a newly picked scene has filled the screen: the end of
/// every scene pick (Tracy, 2026-10-23: 「selecting a new scene always do the open and drop」).
/// One after another, 0.7 s / N apart and me last, each falls from above the screen onto their
/// spot with the drop clip; then the squad's card drops in from the top, 打卡 rises, and the tab
/// bar after it.
///
/// Times count from the moment the picked scene covers the screen (`Unboxing.covered`), and
/// every number is the approved 冠军开箱 prototype's, in the design's 390 × 844 stage points
/// with y down.
public struct DropIn: Hashable, Sendable {
    /// Everyone who drops, me included.
    public let count: Int

    public init(count: Int) {
        self.count = max(1, count)
    }

    /// When the figure at `index` starts falling: teammates first, me last.
    public func start(of index: Int) -> Double {
        Self.firstDrop + Double(index) * Self.spread / Double(count)
    }

    /// How long after it starts falling a figure touches the ground (the clip's own landing,
    /// `PlaceholderCharacter.dropLands`).
    public static let land = 0.55

    /// How much higher than the drop clip lifts it a figure starts, in stage points `elapsed`
    /// seconds into its fall, so that it comes from just above the screen's top wherever its
    /// spot is: nothing once it has landed. `clipLift` is how high the clip lifts it, in stage
    /// points (the clip's 420 rig points at the figure's scale).
    public static func lift(at elapsed: Double, spotY: Double, clipLift: Double) -> Double {
        guard elapsed < land else { return 0 }
        let fall = min(1, max(0, elapsed / land))
        return max(0, spotY + aboveTheTop - clipLift) * (1 - pow(fall, 2.2))
    }

    /// How far above its place the squad's card is, in stage points: up out of sight, then
    /// dropping in with an overshoot.
    public func cardOffset(at time: Double) -> Double {
        Tween.mix(-260, 0, Tween.backOut(Tween.progress(time, from: Self.card, lasting: 0.5)))
    }

    /// How far below its place 打卡 is, in stage points.
    public func buttonOffset(at time: Double) -> Double {
        Tween.mix(160, 0, Tween.backOut(Tween.progress(time, from: Self.button, lasting: 0.4)))
    }

    /// How far below its place the tab bar is, in stage points.
    public func tabBarOffset(at time: Double) -> Double {
        Tween.mix(140, 0, Tween.backOut(Tween.progress(time, from: Self.tabBar, lasting: 0.4)))
    }

    /// When the last figure has settled and everything is in place.
    public var finished: Double {
        max(start(of: count - 1) + Self.dropLength, Self.tabBar + 0.4)
    }

    // The prototype's moments, from the covered screen (its 2.8 s).
    static let firstDrop = 0.15
    static let spread = 0.7
    static let card = 1.35
    static let button = 1.8
    static let tabBar = 1.9
    /// The drop clip's length (`PlaceholderCharacter.drop()`).
    public static let dropLength = 1.9
    /// Where a falling figure's feet start: this far above the screen's top.
    static let aboveTheTop = 60.0
}
