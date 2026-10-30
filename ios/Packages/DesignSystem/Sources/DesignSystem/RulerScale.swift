/// The marks on a `TickRuler`: one value every `step` from `range`'s start to its end, a taller
/// mark every `midEvery`, and a long labelled one every `labelEvery`. The ruler snaps to its
/// values only, so a scale holds the rule for what can be picked.
public struct RulerScale: Hashable, Sendable {
    /// How tall a mark stands: the plain step, the middle one, or the long one with a number.
    public enum Mark: Hashable, Sendable {
        case minor
        case mid
        case major
    }

    public let range: ClosedRange<Int>
    public let step: Int
    public let midEvery: Int
    public let labelEvery: Int

    /// `range` must start and end on a step, and `midEvery` and `labelEvery` must be whole steps.
    public init(range: ClosedRange<Int>, step: Int, midEvery: Int, labelEvery: Int) {
        precondition(step > 0, "a ruler needs a positive step")
        precondition((range.upperBound - range.lowerBound) % step == 0, "the range must end on a step")
        precondition(midEvery % step == 0 && labelEvery % step == 0, "marks must fall on steps")
        self.range = range
        self.step = step
        self.midEvery = midEvery
        self.labelEvery = labelEvery
    }

    /// Every value the ruler can stop on, left to right.
    public var values: [Int] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
    }

    /// The value at a mark's position, counted from 0 at the left end; past either end, the end.
    public func value(atIndex index: Int) -> Int {
        let last = (range.upperBound - range.lowerBound) / step
        return range.lowerBound + min(max(index, 0), last) * step
    }

    /// Where `value`'s mark sits, counted from 0 at the left end, after snapping it to the scale.
    public func index(of value: Int) -> Int {
        (snapped(value) - range.lowerBound) / step
    }

    /// The nearest value the ruler can stop on; halfway rounds up.
    public func snapped(_ value: Int) -> Int {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let steps = (clamped - range.lowerBound + step / 2) / step
        return self.value(atIndex: steps)
    }

    /// The value `count` steps on from `value`, held to the range (VoiceOver's swipe up and down).
    public func value(_ value: Int, movedBy count: Int) -> Int {
        self.value(atIndex: index(of: value) + count)
    }

    /// Marks count from zero, so 15, 30, 45 are long on a minutes ruler that starts at 1.
    public func mark(for value: Int) -> Mark {
        if value % labelEvery == 0 { return .major }
        if value % midEvery == 0 { return .mid }
        return .minor
    }
}
