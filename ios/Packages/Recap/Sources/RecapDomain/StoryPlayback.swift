/// Plays the story's pages like a phone story: each page runs for its own time, then the next
/// one; a tap on the right goes on, on the left goes back; holding pauses. The last page stays
/// up (its 存图 and 排下周 wait for the reader) once its time has run.
///
/// Times are seconds on any clock that only goes forward; the struct never reads one itself.
public struct StoryPlayback: Hashable, Sendable {
    /// Each page's running time, in seconds.
    public let durations: [Double]
    public private(set) var index: Int
    /// False while VoiceOver reads the page, or a UI test drives it: pages still play, but only
    /// a tap moves on.
    public var autoAdvances = true
    /// When the current page began, moved on by however long it was paused.
    private var start: Double
    private var pausedAt: Double?

    public init(durations: [Double], startingAt time: Double) {
        precondition(!durations.isEmpty, "A story has at least its ending")
        self.durations = durations
        index = 0
        start = time
    }

    public var isLast: Bool { index == durations.count - 1 }
    public var isPaused: Bool { pausedAt != nil }

    /// Seconds into the current page, at most its running time.
    public func elapsed(at time: Double) -> Double {
        min(max((pausedAt ?? time) - start, 0), durations[index])
    }

    /// Moves on past every page whose time has run by `time`. True when the page changed.
    @discardableResult
    public mutating func advance(to time: Double) -> Bool {
        guard pausedAt == nil, autoAdvances else { return false }
        var changed = false
        while !isLast, time - start >= durations[index] {
            start += durations[index]
            index += 1
            changed = true
        }
        return changed
    }

    /// The next page, from its start. False on the last page: the reader is done.
    public mutating func next(at time: Double) -> Bool {
        guard !isLast else { return false }
        go(to: index + 1, at: time)
        return true
    }

    /// The page before, from its start; the first page starts again.
    public mutating func previous(at time: Double) {
        go(to: max(index - 1, 0), at: time)
    }

    public mutating func pause(at time: Double) {
        if pausedAt == nil { pausedAt = time }
    }

    public mutating func resume(at time: Double) {
        guard let pausedAt else { return }
        start += time - pausedAt
        self.pausedAt = nil
    }

    /// How full each page's segment in the bar on top is, from 0 to 1.
    public func segments(at time: Double) -> [Double] {
        durations.indices.map { page in
            if page < index { return 1 }
            if page > index { return 0 }
            return elapsed(at: time) / durations[page]
        }
    }

    private mutating func go(to page: Int, at time: Double) {
        index = page
        start = time
        if pausedAt != nil { pausedAt = time }
    }
}

extension StoryPage {
    /// How long the page plays before the next one: its animation plus time to read it.
    public var duration: Double {
        switch self {
        case .pending: 5
        case .podium: 6.5
        case .titles(let rows): min(3 + Double(rows.count), 9)
        case .myWeek(let week): MyWeekBeats(days: week.days).end + 1.5
        case .hottest: 5.5
        case .meals: 6
        case .bestDisclaimer: 6.5
        case .ending: 4.5
        }
    }
}

/// 你的一周's timing: the reader's character lands on Monday, does that day, hops to Tuesday,
/// and so on to Sunday.
public struct MyWeekBeats: Hashable, Sendable {
    public struct Beat: Hashable, Sendable {
        public let day: Int
        /// When the character lands on the day, and when its move ends.
        public let land: Double
        public let end: Double
        public let clip: StoryClip?
    }

    /// Seconds a hop to the next day takes.
    public static let hop = 0.3
    public let beats: [Beat]

    public init(days: [MyWeek.Day]) {
        var time = 0.2
        var beats: [Beat] = []
        for (index, day) in days.enumerated() {
            let clip = day.kind.clip
            // A day with nothing checked in is only passed over.
            let length: Double =
                switch clip {
                case nil: 0.4
                case .sport?: 1.1
                default: 1.0
                }
            beats.append(Beat(day: index, land: time, end: time + length, clip: clip))
            time += length + Self.hop
        }
        self.beats = beats
    }

    /// When the last day's move ends.
    public var end: Double { beats.last?.end ?? 0 }

    /// The day the character is on or hopping from at `time`, nil before Monday.
    public func beat(at time: Double) -> Beat? {
        beats.last { $0.land <= time }
    }
}
