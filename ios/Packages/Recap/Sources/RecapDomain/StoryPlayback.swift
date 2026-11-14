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
        case .myWeek: 4
        case .squadWeek: 5
        case .hottest: 5.5
        case .meals: 6
        case .bestDisclaimer: 6.5
        case .menu: 6
        case .favoritePlace: 5.5
        case .discovery: 5.5
        case .ending: 4.5
        }
    }
}
