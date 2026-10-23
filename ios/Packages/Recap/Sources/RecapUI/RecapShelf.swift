#if os(iOS)
import AvatarArt
import AvatarDomain
import Contracts
import DesignSystem
import Foundation
import Observation
import RecapDomain
import ScenePickDomain

/// Where the app keeps the squad's latest 战报: the story 动态's tile opens, and the one a tapped
/// awards push opens. It reads the story from its service and the squad (who is in it, how they
/// look, the reader's day) from the app.
@MainActor @Observable
public final class RecapShelf {
    /// The squad the story is about, as the app last read it.
    public struct Squad: Sendable {
        public let id: SquadID
        /// The reader's day, in their own time zone.
        public let today: LocalDay
        public let cast: StoryCast

        public init(id: SquadID, today: LocalDay, cast: StoryCast) {
            self.id = id
            self.today = today
            self.cast = cast
        }
    }

    /// The newest story out: this week's once Sunday's awards are in, else last week's. Nil
    /// until one is read, or when the squad is too new to have one.
    public private(set) var latest: WeekStory?
    /// The story on screen.
    public var open: RecapModel?
    /// Who is in the squad, for the tile's peeking reader.
    public private(set) var cast: StoryCast?
    /// How many scenes the reader picked on a story's last page, counted as each reveal fills
    /// the screen: the app goes home onto the scene, the same one as last time or not.
    public private(set) var picks = 0

    @ObservationIgnored private let service: any WeekStoryService
    @ObservationIgnored private let readSquad: @MainActor () -> Squad?
    @ObservationIgnored private let planNextWeek: @MainActor () -> Void
    @ObservationIgnored private let scenePicker: @MainActor (WeekStory) async -> ScenePicker?
    @ObservationIgnored private let scenePicked: @MainActor (SceneTheme) -> Void

    /// - Parameters:
    ///   - squad: the squad and its people as the app holds them now; nil before the home loads.
    ///   - planNextWeek: 排下周 on the last page.
    ///   - scenePicker: the scene pick for the story's last page when the reader picks the scene
    ///     for the week after it (last week's crown winner, else the captain, as the API says)
    ///     and nobody has yet; nil otherwise.
    ///   - scenePicked: the reader picked, and the reveal filled the screen with that scene.
    public init(
        service: any WeekStoryService, squad: @escaping @MainActor () -> Squad?,
        planNextWeek: @escaping @MainActor () -> Void = {},
        scenePicker: @escaping @MainActor (WeekStory) async -> ScenePicker? = { _ in nil },
        scenePicked: @escaping @MainActor (SceneTheme) -> Void = { _ in }
    ) {
        self.service = service
        readSquad = squad
        self.planNextWeek = planNextWeek
        self.scenePicker = scenePicker
        self.scenePicked = scenePicked
    }

    /// Reads the newest story: this week's, which is out from Sunday 8pm Eastern, else last
    /// week's. A failed read keeps the one already shown.
    public func refresh() async {
        guard let squad = readSquad() else { return }
        cast = squad.cast
        let thisWeek = squad.today.weekStart
        do {
            if let story = try await service.story(squad: squad.id, week: thisWeek) {
                latest = story
            } else {
                latest = try await service.story(squad: squad.id, week: thisWeek.adding(days: -7))
            }
        } catch {
            return
        }
    }

    /// Opens the newest story, from 动态's tile.
    public func openLatest() {
        guard let latest, let cast else { return }
        show(latest, cast: cast)
    }

    /// Opens the week a tapped awards push is about, once it can be read.
    public func open(squad id: SquadID, week monday: LocalDay) async {
        guard let squad = readSquad(), squad.id == id else { return }
        cast = squad.cast
        guard let story = try? await service.story(squad: id, week: monday) else { return }
        if monday >= (latest?.week.monday ?? monday) { latest = story }
        show(story, cast: squad.cast)
    }

    private func show(_ story: WeekStory, cast: StoryCast) {
        let model = RecapModel(
            story: story, cast: cast, service: service,
            close: { [weak self] in self?.open = nil },
            planNextWeek: { [weak self] in
                self?.open = nil
                self?.planNextWeek()
            },
            scenePicked: { [weak self] scene in
                self?.open = nil
                self?.picks += 1
                self?.scenePicked(scene)
            })
        open = model
        // The sticker joins the last page once the squad's scene is read, long before the
        // reader gets there.
        let lookup = scenePicker
        Task { model.scenePicker = await lookup(story) }
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
        RecapShelf.Squad(id: story().squad, today: today, cast: cast)
    }

    /// The sample squad's story for any week, for the app without a backend and its UI tests.
    public struct Service: WeekStoryService {
        public init() {}

        public func story(squad: SquadID, week monday: LocalDay) async throws(RecapError) -> WeekStory? {
            RecapSample.story()
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
