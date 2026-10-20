#if os(iOS)
import Foundation
import Observation
import RecapDomain

/// The open story: its pages and the player that walks through them. The view reads it every
/// display frame; taps and holds go through here.
@MainActor @Observable
public final class RecapModel {
    public let story: WeekStory
    public let cast: StoryCast
    let pages: [StoryPage]
    let wardrobe: StoryWardrobe
    private(set) var playback: StoryPlayback
    /// Clip and page times count from here, so they stay small and precise.
    private let epoch: Date
    private let close: @MainActor () -> Void
    let planNextWeek: @MainActor () -> Void
    private let service: (any WeekStoryService)?
    /// The reader nudged the organizers about the late titles.
    private(set) var nudged = false

    /// - Parameters:
    ///   - close: the reader is done: the ✕, a swipe down, or a tap past the last page.
    ///   - planNextWeek: 排下周 on the last page.
    ///   - service: where 催一下主办方 goes; nil for the sample, whose nudge only shows.
    public init(
        story: WeekStory, cast: StoryCast, service: (any WeekStoryService)?, now: Date = .now,
        close: @escaping @MainActor () -> Void, planNextWeek: @escaping @MainActor () -> Void
    ) {
        self.service = service
        self.story = story
        self.cast = cast
        self.close = close
        self.planNextWeek = planNextWeek
        pages = story.pages
        wardrobe = StoryWardrobe(cast: cast)
        epoch = now
        playback = StoryPlayback(durations: pages.map(\.duration), startingAt: 0)
    }

    func seconds(_ date: Date) -> Double { date.timeIntervalSince(epoch) }

    /// The page on screen at `date` and how far into it, moving on past pages whose time ran.
    func frame(at date: Date) -> (index: Int, elapsed: Double) {
        let now = seconds(date)
        // Reading a frame mustn't write the observed state while SwiftUI draws; the timeline
        // asks again next frame, so the advance happens in `tick`.
        var copy = playback
        copy.advance(to: now)
        return (copy.index, copy.elapsed(at: now))
    }

    func segments(at date: Date) -> [Double] {
        var copy = playback
        copy.advance(to: seconds(date))
        return copy.segments(at: seconds(date))
    }

    /// Catches the stored player up with the clock, once per page change.
    func tick(_ date: Date) {
        playback.advance(to: seconds(date))
    }

    func next(_ date: Date = .now) {
        tick(date)
        if !playback.next(at: seconds(date)) { close() }
    }

    func previous(_ date: Date = .now) {
        tick(date)
        playback.previous(at: seconds(date))
    }

    /// Pages move on by themselves unless VoiceOver is reading them, or a UI test drives them.
    func autoAdvance(_ isOn: Bool, _ date: Date = .now) {
        tick(date)
        playback.autoAdvances = isOn
    }

    func hold(_ isHeld: Bool, _ date: Date = .now) {
        tick(date)
        if isHeld { playback.pause(at: seconds(date)) } else { playback.resume(at: seconds(date)) }
    }

    public func dismiss() { close() }

    /// 催一下主办方. It always lands as far as the reader can tell: a nudge that doesn't reach the
    /// API changes nothing they could act on, and the hourly retry runs anyway.
    func nudge() {
        nudged = true
        guard let service else { return }
        let squad = story.squad
        let monday = story.week.monday
        Task { try? await service.nudge(squad: squad, week: monday) }
    }
}
#endif
