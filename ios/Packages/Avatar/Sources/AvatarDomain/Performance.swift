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
    /// What stays on screen until the playing clip starts, when `play` waits for an arm to clear
    /// the body.
    private var waiting: Change?

    private final class Change: Sendable {
        /// When the new outfit goes on, or the waiting clip starts.
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
        /// Whether the outfit went on as it began, so the frame before showed another drawing.
        var dressed = false
        /// When each arm that changes depth as the clip blends in does, in seconds since it began.
        var swaps: [DepthSwap] = []
        /// The same for a one-shot handing back to idle, in seconds since it ended.
        var handBack: [DepthSwap] = []

        /// The most of a forearm over the body any change of depth as it blends in shows.
        var shows: Double { swaps.map(\.shows).max() ?? 0 }
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
        plan()
    }

    /// Starts a clip now, blending from whatever is on screen, or cutting straight to its first
    /// frame without `blending` (the entrance, which starts off stage: blending would slide the
    /// character out from its spot first). A change of clothes still under way stops where it
    /// is, in the clothes on screen, and a clip still waiting to start never does.
    ///
    /// When an arm must change depth as the clip blends in and its forearm is over the body
    /// all the while (a run's swing, say, into a bottle held in front), the clip waits, at most
    /// `DepthSwap.reach`, for the frame where the forearm on screen is clear, so it can change
    /// depth unseen as the blend begins.
    public mutating func play(_ clip: BoundClip, at time: Double, blending: Bool = true) {
        play(clip, at: time, blending: blending, waiting: true)
    }

    private mutating func play(_ clip: BoundClip, at time: Double, blending: Bool, waiting canWait: Bool) {
        settle(at: time)
        if let waiting, time < waiting.swap { self = waiting.performance }
        (change, waiting) = (nil, nil)
        guard blending else {
            current = Playing(clip: clip, start: time, from: nil)
            plan()
            return
        }
        let onScreen = self
        current = Playing(clip: clip, start: time, from: onScreen.pose(at: time))
        planBlendIn()
        defer { planHandBack() }
        let seen = current.swaps.filter { $0.shows > DepthSwap.unseen }.map(\.part)
        func clear(_ pose: Pose) -> Bool { seen.allSatisfy { figure.depthSwapShows($0, in: pose) <= DepthSwap.unseen } }
        // Waiting helps only when the forearm on screen is over the body now and clears later.
        guard canWait, !seen.isEmpty, !clear(onScreen.pose(at: time)) else { return }
        // The screen's last frame before the clip starts may be a little earlier, so the frame
        // before must be clear too. Every other frame first, the most of the measuring.
        for frame in stride(from: 2, through: Int((DepthSwap.reach * 60).rounded()), by: 2) {
            let start = time + Double(frame) / 60
            let pose = onScreen.pose(at: start)
            guard clear(pose), clear(onScreen.pose(at: start - 1.0 / 60)) else { continue }
            var later = onScreen
            later.waiting = Change(swap: start, performance: onScreen)
            later.current = Playing(clip: clip, start: start, from: pose)
            later.planBlendIn()
            if later.current.shows < current.shows { self = later }
            return
        }
    }

    /// Changes clothes with a hop: `leaving` plays in the clothes on screen (a squash down),
    /// `figure` takes over on its last frame and plays `arriving` (the pop back up), then `idle`
    /// (a sport's move). `arriving` blends on from the pose on screen at the swap, so nothing
    /// snaps when `leaving` is shorter than a blend. Both figures come from the same rig.
    public mutating func change(
        into figure: Figure, idle: BoundClip, leaving: BoundClip, arriving: BoundClip, at time: Double
    ) {
        // The hop starts on time, so the swap lands on its last frame.
        play(leaving, at: time, blending: true, waiting: false)
        // `leaving` hands over to `arriving`, never back to this idle.
        current.handBack = []
        let swap = time + leaving.clip.duration
        var next = Performance(figure: figure, idle: idle, startingAt: swap, blendDuration: blendDuration)
        // Where `leaving` ends up on screen, its blend in included.
        let end = self.figure.pose(leaving, at: leaving.clip.duration)
        let handOver = current.from.map { blend(from: $0, to: end, since: leaving.clip.duration) } ?? end
        next.current = Playing(
            clip: arriving, start: swap, from: handOver.parts.count == figure.parts.count ? handOver : nil,
            dressed: true)
        next.plan()
        change = Change(swap: swap, performance: next)
    }

    /// The figure on screen at a time: the new outfit once a change has swapped it in.
    public func figure(at time: Double) -> Figure {
        if let change, time >= change.swap { return change.performance.figure(at: time) }
        return figure
    }

    /// The pose a character holds when it stands still (Reduce Motion): its idle's first frame,
    /// in the outfit a change of clothes ends up in, so a face the idle sets (near tears, say)
    /// stays on.
    public var stillPose: Pose {
        if let change { return change.performance.stillPose }
        return figure.pose(idle, at: 0)
    }

    /// The clip on screen at a time: a one-shot clip that has ended is idle again.
    public func clipName(at time: Double) -> String {
        if let change, time >= change.swap { return change.performance.clipName(at: time) }
        if let waiting, time < waiting.swap { return waiting.performance.clipName(at: time) }
        return finishedOneShot(at: time) == nil ? current.clip.clip.name : idle.clip.name
    }

    public func pose(at time: Double) -> Pose {
        if let change, time >= change.swap { return change.performance.pose(at: time) }
        if let waiting, time < waiting.swap { return waiting.performance.pose(at: time) }
        if let end = finishedOneShot(at: time) {
            // Idle restarts from its first frame, blended from the one-shot's last.
            let last = figure.pose(current.clip, at: current.clip.clip.duration)
            var pose = blend(from: last, to: figure.pose(idle, at: time - end), since: time - end)
            current.handBack.apply(to: &pose, at: time - end)
            return pose
        }
        let elapsed = time - current.start
        var pose = figure.pose(current.clip, at: elapsed)
        if let from = current.from { pose = blend(from: from, to: pose, since: elapsed) }
        current.swaps.apply(to: &pose, at: elapsed)
        if !current.clip.clip.loops { current.handBack.apply(to: &pose, at: elapsed - current.clip.clip.duration) }
        return pose
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

    /// Picks when each arm that changes depth as the playing clip blends in, and (a one-shot) as
    /// it hands back to idle, does: on a frame where its forearm doesn't show over the body
    /// (`Figure.depthSwapShows`), so the change can't be seen, whatever the clips on either side
    /// (a sport's move is an idle too, and holds its arms anywhere). It looks from the blend's
    /// start until the clip's own next change of that arm's depth, at most `DepthSwap.reach` past
    /// the blend, and, handing back, from as far before the end; nearest the blend's start first,
    /// clear a 60 Hz screen frame either side. With none clear, an arm the clip itself changes back
    /// within that span keeps its depth throughout; else it changes on the frame that shows least,
    /// which `play` may avoid by waiting. Run once as a clip starts.
    private mutating func plan() {
        planBlendIn()
        planHandBack()
    }

    private mutating func planBlendIn() {
        let (performance, clip) = (self, current.clip)
        guard let from = current.from else { return }
        // A one-shot's changes land before it ends; handing back plans the rest.
        let latest =
            clip.clip.loops ? blendDuration + DepthSwap.reach : min(blendDuration + DepthSwap.reach, clip.clip.duration)
        current.swaps = performance.depthSwaps(
            from: from, earliest: 0, latest: latest, soonest: current.dressed ? 2 : 1
        ) { time in
            let pose = performance.figure.pose(clip, at: time)
            return (performance.blend(from: from, to: pose, since: time), pose.parts)
        }
    }

    private mutating func planHandBack() {
        let (performance, clip) = (self, current.clip)
        guard !clip.clip.loops else { return }
        let length = clip.clip.duration
        let last = figure.pose(clip, at: length)
        // From after the blend in and its changes, which the hand-back mustn't undo.
        let blendIn = current.swaps.map(\.closes).reduce(current.from == nil ? 0 : blendDuration, max)
        let earliest = -max(min(DepthSwap.reach, length - blendIn), 0)
        current.handBack = performance.depthSwaps(from: last, earliest: earliest) { time in
            if time < 0 {
                let pose = performance.figure.pose(clip, at: length + time)
                return (pose, pose.parts)
            }
            let idle = performance.figure.pose(performance.idle, at: time)
            return (performance.blend(from: last, to: idle, since: time), idle.parts)
        }
    }

    /// For each arm whose depth in `start` differs from the one keyed once the blend is over,
    /// when it changes. `frame(t)` gives the pose on screen `t` seconds after the blend starts,
    /// and the poses the clips key then, whose depths bound where the change may go; it looks no
    /// later than `latest`, nor sooner than frame `soonest` of the blend.
    private func depthSwaps(
        from start: Pose, earliest: Double, latest: Double = .infinity, soonest: Int = 1,
        frame: (Double) -> (pose: Pose, keyed: [PartPose])
    ) -> [DepthSwap] {
        guard start.parts.count == figure.parts.count, blendDuration > 0 else { return [] }
        let rate = DepthSwap.rate
        let first = Int((earliest * rate).rounded(.down))
        let last = Int((min(latest, blendDuration + DepthSwap.reach) * rate).rounded(.down))
        let frames = (first...max(first, last)).map {
            frame(Double($0) / rate)
        }
        let origin = -first
        let settle = origin + Int((blendDuration * rate).rounded(.up))
        // A clip over before its blend is: it hands back from wherever it is.
        guard settle < frames.count else { return [] }
        var swaps: [DepthSwap] = []
        for part in figure.parts.indices where figure.parts[part].front {
            let keyed = frames.map { $0.keyed[part].front >= 0.5 }
            let (before, after) = (start.parts[part].front >= 0.5, keyed[settle])
            guard before != after else { continue }
            let (open, close) = Self.window(keyed, before: before, after: after, origin: origin, settle: settle)
            // Not before `soonest`: where the frame before a clip shows another outfit, two frames in,
            // so the screen frame before the change shows this one too.
            let soonest = max(open + 1, soonest)
            guard soonest < close else { continue }
            var shows: [Int: Double] = [:]
            func shown(_ index: Int) -> Double {
                if let known = shows[index] { return known }
                let area = figure.depthSwapShows(part, in: frames[index].pose)
                shows[index] = area
                return area
            }
            let order = (soonest..<close).sorted { abs($0 - origin) < abs($1 - origin) }
            var best = (index: order[0], shows: Double.infinity)
            for index in order {
                // A screen frame either side of it, wherever the screen's frames fall. Every fourth
                // frame first, which each such span holds one of: where it shows, so does the span,
                // and the rest needn't be measured (it is the most of the measuring, on a tap).
                let span = (index - 2...index + 1).map { min(max($0, 0), frames.count - 1) }
                let probe = span.first { $0 % 4 == 0 } ?? span[0]
                let area = shown(probe) > DepthSwap.unseen ? shown(probe) : span.map(shown).max() ?? 0
                if area < best.shows { best = (index, area) }
                if area <= DepthSwap.unseen { break }
            }
            // No clear frame before the clip changes back by itself: keep the depth until then.
            if best.shows > DepthSwap.unseen, close < keyed.count { best = (close, 0) }
            swaps.append(
                DepthSwap(
                    part: part, before: before ? 1 : 0, after: after ? 1 : 0, opens: Double(open + first) / rate,
                    turn: Double(best.index + first) / rate, closes: Double(close + first) / rate,
                    shows: best.shows))
        }
        return swaps
    }

    /// Where a change may land: from the clip's own last change before the blend (`origin`) to its
    /// next after the blend is over (`settle`), as frame indexes into `keyed`.
    private static func window(_ keyed: [Bool], before: Bool, after: Bool, origin: Int, settle: Int) -> (
        open: Int, close: Int
    ) {
        let open = (0..<origin).last { keyed[$0] != before }.map { $0 + 1 } ?? 0
        let close = (settle..<keyed.count).first { keyed[$0] != after } ?? keyed.count
        return (open, close)
    }
}

/// When an arm changes depth around a blend: from `opens` until `turn` it keeps `before`, then
/// until `closes` it is `after`, whatever the blended poses say; outside, the clips' own keys stand.
/// Seconds since the clip began (blending in) or ended (handing back).
struct DepthSwap: Sendable {
    var part: Int
    var before: Double
    var after: Double
    var opens: Double
    var turn: Double
    var closes: Double
    /// How much of the forearm over the body the change shows, the frames either side of `turn`.
    var shows: Double

    /// How far past a blend, and before a one-shot's end, a change may move to find a clear frame.
    static let reach = 0.45
    /// Frames a second the planner looks at: two to each of a 60 Hz screen's.
    static let rate = 120.0
    /// Square points of forearm over the body a change may show and still not be seen: a sliver
    /// along an outline, where both drawings agree.
    static let unseen = 4.0
}

extension [DepthSwap] {
    func apply(to pose: inout Pose, at time: Double) {
        for swap in self where time >= swap.opens && time < swap.closes {
            pose.parts[swap.part].front = time < swap.turn ? swap.before : swap.after
        }
    }
}
