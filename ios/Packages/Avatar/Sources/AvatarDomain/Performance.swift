/// What a character is doing over time: an idle loop, and clips played on top of it. A
/// one-shot clip, like a cheer, hands back to idle when it ends; a looping clip keeps
/// going until the next `play`. Changes blend over a short crossfade so nothing snaps. A
/// character can also change clothes partway (`change`), as it does when a sport is picked.
///
/// Times are seconds on any clock the caller picks, as long as it only goes forward.
/// The struct never reads a clock itself, so tests drive it frame by frame.
public struct Performance: Sendable {
    /// The figure on screen until a change of clothes swaps in another (`figure(at:)`).
    public let figure: Figure
    public let idle: BoundClip
    /// Seconds a change of clip takes to blend in.
    public let blendDuration: Double

    private var current: Playing
    /// A change of clothes under way: from `at`, the performance in the new outfit takes over.
    private var change: Change?

    private final class Change: Sendable {
        /// When the new outfit goes on.
        let swap: Double
        let performance: Performance

        init(swap: Double, performance: Performance) {
            (self.swap, self.performance) = (swap, performance)
        }
    }

    private struct Playing: Sendable {
        var clip: BoundClip
        var start: Double
        /// The pose on screen when this clip began, to blend from.
        var from: Pose?
    }

    public init(figure: Figure, idle: BoundClip, startingAt time: Double = 0, blendDuration: Double = 0.15) {
        self.figure = figure
        self.idle = idle
        self.blendDuration = blendDuration
        current = Playing(clip: idle, start: time, from: nil)
    }

    /// Carries on from `previous` in another outfit or with another idle, such as a character
    /// being dressed in the editor: the new idle starts at `time`, blending from the pose
    /// `previous` shows then. Both figures come from the same rig, so the poses line up; if they
    /// don't, the new idle starts without a blend.
    public init(continuing previous: Performance, figure: Figure, idle: BoundClip, at time: Double) {
        self.init(figure: figure, idle: idle, startingAt: time, blendDuration: previous.blendDuration)
        let onScreen = previous.pose(at: time)
        if onScreen.parts.count == figure.parts.count {
            current.from = onScreen
        }
    }

    /// Starts a clip now, blending from whatever is on screen, or cutting straight to its first
    /// frame without `blending` (the entrance, which starts off stage: blending would slide the
    /// character out from its spot first). A change of clothes still under way stops where it
    /// is, in the clothes on screen.
    public mutating func play(_ clip: BoundClip, at time: Double, blending: Bool = true) {
        settle(at: time)
        let onScreen = blending ? pose(at: time) : nil
        change = nil
        current = Playing(clip: clip, start: time, from: onScreen)
    }

    /// Changes clothes with a hop: `leaving` plays in the clothes on screen (a squash down),
    /// `figure` takes over on its last frame and plays `arriving` (the pop back up), then `idle`
    /// (a sport's move). Both figures come from the same rig.
    public mutating func change(
        into figure: Figure, idle: BoundClip, leaving: BoundClip, arriving: BoundClip, at time: Double
    ) {
        play(leaving, at: time)
        let swap = time + leaving.clip.duration
        var next = Performance(figure: figure, idle: idle, startingAt: swap, blendDuration: blendDuration)
        next.current = Playing(clip: arriving, start: swap, from: nil)
        change = Change(swap: swap, performance: next)
    }

    /// The figure on screen at a time: the new outfit once a change has swapped it in.
    public func figure(at time: Double) -> Figure {
        if let change, time >= change.swap { return change.performance.figure(at: time) }
        return figure
    }

    /// The clip on screen at a time: a one-shot clip that has ended is idle again.
    public func clipName(at time: Double) -> String {
        if let change, time >= change.swap { return change.performance.clipName(at: time) }
        return finishedOneShot(at: time) == nil ? current.clip.clip.name : idle.clip.name
    }

    public func pose(at time: Double) -> Pose {
        if let change, time >= change.swap { return change.performance.pose(at: time) }
        if let end = finishedOneShot(at: time) {
            // Idle restarts from its first frame, blended from the one-shot's last.
            let last = figure.pose(current.clip, at: current.clip.clip.duration)
            return blend(from: last, to: figure.pose(idle, at: time - end), since: time - end)
        }
        let pose = figure.pose(current.clip, at: time - current.start)
        guard let from = current.from else { return pose }
        return blend(from: from, to: pose, since: time - current.start)
    }

    /// Becomes the performance in the new outfit once a change has swapped it in by `time`.
    private mutating func settle(at time: Double) {
        if let change, time >= change.swap { self = change.performance }
    }

    /// When the playing clip is a one-shot that has ended by `time`, the time it ended.
    private func finishedOneShot(at time: Double) -> Double? {
        let clip = current.clip.clip
        guard !clip.loops else { return nil }
        let end = current.start + clip.duration
        return time >= end ? end : nil
    }

    private func blend(from start: Pose, to target: Pose, since elapsed: Double) -> Pose {
        guard elapsed < blendDuration, blendDuration > 0 else { return target }
        let fraction = max(elapsed, 0) / blendDuration
        // Smoothstep: starts and ends gently.
        return start.blended(to: target, amount: fraction * fraction * (3 - 2 * fraction))
    }
}
