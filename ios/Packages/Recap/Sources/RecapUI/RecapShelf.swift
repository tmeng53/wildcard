#if os(iOS)
import AvatarArt
import AvatarDomain
import Contracts
import DesignSystem
import Foundation
import Observation
import RecapDomain
import ScenePickDomain
import SwiftUI

/// Where the app keeps the squad's 战报 (每周战报): the latest, which 动态's tile opens until the
/// reader watched it to the end, and every one before it, which 往期战报 on 小队 opens. It reads
/// them from its service, which carries the squad as it was each week, and the reader and their
/// day from the app. It remembers on this phone which weeks the reader watched to the end, for
/// the tile and the covers.
@MainActor @Observable
public final class RecapShelf {
    /// The squad the reader is in and their day, as the app last read them.
    public struct Squad: Sendable {
        public let id: SquadID
        /// The reader's day, in their own time zone.
        public let today: LocalDay
        public let viewer: MemberID

        public init(id: SquadID, today: LocalDay, viewer: MemberID) {
            self.id = id
            self.today = today
            self.viewer = viewer
        }
    }

    /// The newest story out: this week's once Sunday's awards are in, else last week's. Nil
    /// until one is read, or when neither week's 战报 came out (a squad too new to have one).
    public private(set) var latest: WeekStory?
    /// Every story the squad has, the latest first (往期战报); empty until read, and for a squad
    /// whose first week isn't over.
    public private(set) var past: [WeekStory] = []
    /// The story on screen.
    public var open: RecapModel?
    /// Who was in the squad that week, for the tile's reader.
    public var cast: StoryCast? {
        guard let latest, let viewer else { return nil }
        return StoryCast(story: latest, viewer: viewer)
    }
    /// The reader watched the newest story to its last page on this phone: 动态 stops showing its
    /// tile, and the story stays on 小队's 往期战报.
    public var latestIsSeen: Bool {
        latest.map(isSeen) ?? false
    }
    /// The squadmate reading, as each story keeps them.
    public var reader: MemberID? { viewer }
    private var viewer: MemberID?
    private var seen: Set<String>
    /// How many scenes the reader picked on a story's last page, counted as each reveal fills
    /// the screen: the app goes home onto the scene, the same one as last time or not, and the
    /// squad drops in.
    public private(set) var picks = 0
    /// The scene picked last, and when it filled the screen.
    public private(set) var picked: (scene: SceneTheme, coveredAt: Date)?

    @ObservationIgnored private let service: any WeekStoryService
    @ObservationIgnored private let readSquad: @MainActor () -> Squad?
    @ObservationIgnored private let planNextWeek: @MainActor () -> Void
    @ObservationIgnored private let scenePicker: @MainActor (WeekStory) async -> ScenePicker?
    @ObservationIgnored private let scenePicked: @MainActor (SceneTheme) -> Void
    @ObservationIgnored private let seenStore: RecapSeen

    /// - Parameters:
    ///   - squad: the squad and its people as the app holds them now; nil before the home loads.
    ///   - planNextWeek: 排下周 on the last page.
    ///   - scenePicker: the scene pick for the story's last page when the reader picks the scene
    ///     for the week after it (last week's crown winner, else the captain, as the API says)
    ///     and nobody has yet; nil otherwise.
    ///   - scenePicked: the reader picked, and the reveal filled the screen with that scene.
    ///   - seen: where the weeks watched to the end are kept.
    public init(
        service: any WeekStoryService, squad: @escaping @MainActor () -> Squad?, seen: RecapSeen = RecapSeen(),
        planNextWeek: @escaping @MainActor () -> Void = {},
        scenePicker: @escaping @MainActor (WeekStory) async -> ScenePicker? = { _ in nil },
        scenePicked: @escaping @MainActor (SceneTheme) -> Void = { _ in }
    ) {
        self.service = service
        readSquad = squad
        self.planNextWeek = planNextWeek
        self.scenePicker = scenePicker
        self.scenePicked = scenePicked
        seenStore = seen
        self.seen = seen.weeks()
    }

    /// Reads the newest story out: this week's, from Sunday 8pm Eastern, else last week's; a week
    /// whose 战报 never came out shows none. A failed read keeps the one already shown.
    public func refresh() async {
        guard let squad = readSquad() else { return }
        viewer = squad.viewer
        let thisWeek = squad.today.weekStart
        do {
            if let story = try await service.story(squad: squad.id, week: thisWeek), story.isPublished {
                latest = story
            } else {
                let lastWeek = try await service.story(squad: squad.id, week: thisWeek.adding(days: -7))
                latest = lastWeek?.isPublished == true ? lastWeek : nil
            }
        } catch {
            return
        }
    }

    /// Reads every story the squad has, for 往期战报, each time: a story's photo links last an
    /// hour, and a deleted post or photo leaves it. A week that fails to read keeps the copy
    /// already shown, else is left out until the next read.
    public func refreshPast() async {
        guard let squad = readSquad() else { return }
        viewer = squad.viewer
        let weeks: [LocalDay]
        do {
            weeks = try await service.weeks(squad: squad.id)
        } catch {
            return
        }
        let shown = Dictionary(
            past.filter { $0.squad == squad.id }.map { ($0.week.monday, $0) },
            uniquingKeysWith: { first, _ in first })
        let service = service
        let read = await withTaskGroup(of: (LocalDay, WeekStory?).self) { group in
            for week in weeks {
                group.addTask { (week, try? await service.story(squad: squad.id, week: week)) }
            }
            var read: [LocalDay: WeekStory] = [:]
            for await (week, story) in group { read[week] = story }
            return read
        }
        past = weeks.compactMap { read[$0] ?? shown[$0] }.filter(\.isPublished)
    }

    /// Whether the reader watched this story to its last page on this phone.
    public func isSeen(_ story: WeekStory) -> Bool {
        seen.contains(RecapSeen.key(story))
    }

    /// Opens one of the squad's stories, from its cover on 往期战报, read again first so its
    /// photo links are fresh and what was deleted is gone; the copy on the cover if that fails.
    public func open(_ story: WeekStory) async {
        guard let viewer else { return }
        let fresh = try? await service.story(squad: story.squad, week: story.week.monday)
        show(fresh ?? story, viewer: viewer)
    }

    /// Opens the squad's story for the week starting `monday`, from a tapped awards push or its
    /// 通知 row: read now, else the copy already read. Nothing opens for a week without one, or
    /// for another squad's (one the reader has left).
    public func open(week monday: LocalDay, of squadID: SquadID? = nil) async {
        guard let squad = readSquad(), squadID == nil || squadID == squad.id else { return }
        viewer = squad.viewer
        if let story = try? await service.story(squad: squad.id, week: monday) {
            show(story, viewer: squad.viewer)
        } else if let known = ([latest].compactMap { $0 } + past).first(where: {
            $0.squad == squad.id && $0.week.monday == monday
        }) {
            show(known, viewer: squad.viewer)
        }
    }

    /// Opens the newest story, from 动态's tile.
    public func openLatest() {
        guard let latest, let viewer else { return }
        show(latest, viewer: viewer)
    }

    /// Plays a story that came out: one that didn't may have no page at all, which the player
    /// can't start on.
    private func show(_ story: WeekStory, viewer: MemberID) {
        guard story.isPublished else { return }
        let model = RecapModel(
            story: story, cast: StoryCast(story: story, viewer: viewer), service: service,
            close: { [weak self] in self?.open = nil },
            finished: { [weak self] in self?.watched(story) },
            planNextWeek: { [weak self] in
                self?.open = nil
                self?.planNextWeek()
            },
            scenePicked: { [weak self] scene, coveredAt in
                // The story goes at once: the reveal's last frame is the scene home draws.
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { self?.open = nil }
                self?.picked = (scene, coveredAt)
                self?.picks += 1
                self?.scenePicked(scene)
            })
        open = model
        // The sticker joins the last page once the squad's scene is read, long before the
        // reader gets there.
        let lookup = scenePicker
        Task { model.scenePicker = await lookup(story) }
    }

    private func watched(_ story: WeekStory) {
        let key = RecapSeen.key(story)
        guard !seen.contains(key) else { return }
        seen.insert(key)
        seenStore.add(key)
    }
}

/// The weeks whose 战报 the reader watched to the end on this phone, the latest ten years' worth.
/// Only the tile and the covers read it, so losing it only shows them as new again.
public struct RecapSeen: Sendable {
    private let defaults: @Sendable () -> UserDefaults
    private static let entry = "recap.seen"
    private static let kept = 520

    public init(defaults: @escaping @Sendable () -> UserDefaults = { .standard }) {
        self.defaults = defaults
    }

    /// Forgotten at each launch: the sample squad's, so UI tests always start on the cloth.
    public static func onlyThisLaunch() -> RecapSeen {
        let suite = "recap.sample"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return RecapSeen { UserDefaults(suiteName: suite) ?? .standard }
    }

    static func key(_ story: WeekStory) -> String { "\(story.squad)/\(story.week.monday)" }

    func weeks() -> Set<String> {
        Set(defaults().stringArray(forKey: Self.entry) ?? [])
    }

    func add(_ key: String) {
        let kept = (defaults().stringArray(forKey: Self.entry) ?? []).filter { $0 != key }
        defaults().set(Array((kept + [key]).suffix(Self.kept)), forKey: Self.entry)
    }
}

extension StoryMember {
    /// A squadmate as the API keeps them: their nickname and look. Nil for someone who hasn't
    /// made their character yet, whom the story leaves out.
    public init?(member: MemberID, character: MemberCharacter?) {
        guard let character else { return nil }
        let body = character.look.variants["body"]
        self.init(
            id: member, nickname: character.nickname.text, look: Outfit(character.look),
            persona: Persona(character.look),
            species: body.flatMap { body in Self.choices?.species.first { $0.bodies.contains(body) }?.id })
    }

    private static let choices = try? PlaceholderCharacter.editorChoices()
}

extension RecapSample {
    /// The sample squad on `today`, for a shelf on `Service`.
    public static func squad(today: LocalDay) -> RecapShelf.Squad {
        RecapShelf.Squad(id: story().squad, today: today, viewer: cast.viewer)
    }

    /// The sample squad's story for any week, for the app without a backend and its UI tests.
    public struct Service: WeekStoryService {
        public init() {}

        public func story(squad: SquadID, week monday: LocalDay) async throws(RecapError) -> WeekStory? {
            guard let past = RecapSample.pastWeeks.firstIndex(of: monday) else { return RecapSample.story() }
            return RecapSample.story(monday: monday, scene: RecapSample.pastScenes[past])
        }

        public func weeks(squad: SquadID) async throws(RecapError) -> [LocalDay] {
            RecapSample.pastWeeks
        }

        public func nudge(squad: SquadID, week monday: LocalDay) async throws(RecapError) {}
    }

    /// The sample reader picking next week's scene, as in the approved design: the squad trains
    /// at the track this week, was at the pool 5 weeks ago, and has never opened the rest. The
    /// pick always goes through.
    @MainActor
    public static func scenePicker() -> ScenePicker {
        ScenePicker(
            options: [
                SceneOption(scene: .track, lastTrained: .thisWeek),
                SceneOption(scene: .pool, lastTrained: .weeksAgo(5)),
                SceneOption(scene: .gym, lastTrained: .never),
                SceneOption(scene: .tennis, lastTrained: .never),
                SceneOption(scene: .climbing, lastTrained: .never),
            ],
            service: ScenePick())
    }

    private struct ScenePick: ScenePickService {
        func pick(_ scene: SceneTheme) async throws(ScenePickError) {}
    }
}
#endif
