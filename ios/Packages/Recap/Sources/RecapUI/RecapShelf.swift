#if os(iOS)
import AvatarArt
import AvatarDomain
import Contracts
import DesignSystem
import Foundation
import Observation
import RecapDomain

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

    @ObservationIgnored private let service: any WeekStoryService
    @ObservationIgnored private let readSquad: @MainActor () -> Squad?
    @ObservationIgnored private let planNextWeek: @MainActor () -> Void
    @ObservationIgnored private let pickScene: (@MainActor (WeekStory) -> Void)?

    /// - Parameters:
    ///   - squad: the squad and its people as the app holds them now; nil before the home loads.
    ///   - planNextWeek: 排下周 on the last page.
    ///   - pickScene: called with the story once the reader closes it, so the scene pick
    ///     (开箱选场地) can open for whoever picks next week's scene; the API says who that is
    ///     (last week's crown winner, else the captain). Nil until that screen is wired.
    public init(
        service: any WeekStoryService, squad: @escaping @MainActor () -> Squad?,
        planNextWeek: @escaping @MainActor () -> Void = {}, pickScene: (@MainActor (WeekStory) -> Void)? = nil
    ) {
        self.service = service
        readSquad = squad
        self.planNextWeek = planNextWeek
        self.pickScene = pickScene
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
        open = RecapModel(
            story: story, cast: cast, service: service,
            close: { [weak self] in
                self?.open = nil
                self?.pickScene?(story)
            },
            planNextWeek: { [weak self] in
                self?.open = nil
                self?.planNextWeek()
            })
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
}
#endif
