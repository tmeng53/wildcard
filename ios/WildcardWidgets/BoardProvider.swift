import AppIntents
import Backend
import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation
import HomeWidgetDomain
import HomeWidgetUI
import SportsUI
import WidgetKit

/// One moment of a widget: the board then, or why there is none, and which side it shows.
struct BoardEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
    let side: WidgetSide

    /// A coach with a card I haven't seen comes to the top of a Smart Stack.
    var relevance: TimelineEntryRelevance? {
        guard side == .coach, case .board(let board) = state, board.coach?.hasNews == true else {
            return TimelineEntryRelevance(score: 0)
        }
        return TimelineEntryRelevance(score: 1)
    }
}

/// Which side the medium widget shows, picked when the widget is edited: 小队 or 教练. Two of
/// them stacked are both sides, a swipe apart.
enum WidgetSide: String, AppEnum {
    case squad
    case coach

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "显示"
    static let caseDisplayRepresentations: [WidgetSide: DisplayRepresentation] = [
        .squad: "小队", .coach: "教练",
    ]
}

/// 我的一周 has nothing to set; WidgetKit's async provider needs an intent all the same.
struct WeekIntent: WidgetConfigurationIntent, ShowsSide {
    static let title: LocalizedStringResource = "我的一周"
    static let readsCoach = false
    var side: WidgetSide { .squad }
}

/// The medium widget's one setting: 小队 or 教练.
struct SquadOrCoachIntent: WidgetConfigurationIntent, ShowsSide {
    static let title: LocalizedStringResource = "小队和教练"

    @Parameter(title: "显示", default: .squad) var shown: WidgetSide

    var side: WidgetSide { shown }
}

/// A widget's intent says which side it shows, and whether it shows the coach at all.
protocol ShowsSide {
    var side: WidgetSide { get }
    /// 我的一周 doesn't, so it reads nothing about the coach.
    static var readsCoach: Bool { get }
}

extension ShowsSide {
    static var readsCoach: Bool { true }
}

/// Reads the squad for the widgets: the home over our API, signed in with the app's shared
/// session, or the copy the widget kept when the network fails, with the coach and what it says
/// to me. The app also asks the widgets to read again whenever it leaves the screen, so a post
/// shows at once.
struct BoardProvider<Intent: WidgetConfigurationIntent & ShowsSide>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        Self.sample(at: Date(), side: .squad)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> BoardEntry {
        context.isPreview
            ? Self.sample(at: Date(), side: configuration.side)
            : await Self.read(at: Date(), side: configuration.side).entry
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<BoardEntry> {
        let (entry, zone) = await Self.read(at: Date(), side: configuration.side)
        let next =
            entry.state == .unavailable
            ? entry.date.addingTimeInterval(WidgetState.retryInterval)
            : WidgetBoard.nextLook(after: entry.date, in: zone)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private static func sample(at now: Date, side: WidgetSide) -> BoardEntry {
        BoardEntry(date: now, state: .board(SampleBoard.board(on: LocalDay(at: now, in: .current))), side: side)
    }

    /// The board now, with the clock its day turns on.
    private static func read(at now: Date, side: WidgetSide) async -> (entry: BoardEntry, zone: TimeZone) {
        // The language picked in the app, and the sports' icons from the list this build ships.
        AppLanguage.adopt(from: AppGroup.defaults, folder: AppGroup.directory)
        SportList.shared.show(CatalogClient.bundled.sports)
        let entry = { (state: WidgetState) in (BoardEntry(date: now, state: state, side: side), TimeZone.current) }
        let session: WidgetSession
        switch await WidgetSession.open() {
        case .signedIn(let opened): session = opened
        // A build that names no backend (Debug) runs on the sample squad, as the app does.
        case .sample: return (sample(at: now, side: side), .current)
        // The Keychain is locked until the phone's first unlock after a restart, and so is the
        // widget's copy: try again soon, keeping the copy, rather than say nobody signed in.
        case .locked: return entry(.unavailable)
        // Nobody signed in: the copy goes with them.
        case .signedOut:
            WidgetSession.folders.forgetAll()
            return entry(.signedOut)
        }
        let backend = APICheckInBackend(
            api: session.api, directory: WidgetSession.folders.folder(for: session.member))
        let home: Home
        do {
            guard let read = try await backend.home() else { return entry(.noSquad) }
            home = read
        } catch .signedOut {
            // The session can't be renewed any more.
            WidgetSession.folders.forgetAll()
            return entry(.signedOut)
        } catch {
            guard let saved = await backend.savedHome() else { return entry(.unavailable) }
            home = saved
        }
        var coach: CoachFace?
        if Intent.readsCoach {
            let read = await coachFace(in: home.squad.id, api: session.api, side: side, at: now)
            // The coach's side can't say the squad has no coach when it only couldn't ask: try
            // again soon. The squad's side just leaves the coach's head out.
            if case .unreadable = read, side == .coach { return entry(.unavailable) }
            coach = read.face
        }
        let board = WidgetBoard(home: home, day: LocalDay(at: now, in: home.timeZone), coach: coach)
        return (BoardEntry(date: now, state: .board(board), side: side), home.timeZone)
    }

    /// What reading the coach found.
    private enum CoachRead {
        case face(CoachFace)
        /// The squad has no coach.
        case noCoach
        /// The coach couldn't be read now (offline).
        case unreadable

        var face: CoachFace? {
            if case .face(let face) = self { face } else { nil }
        }
    }

    /// The squad's coach and what it says to me now. Only the coach's side reads what it said
    /// and today's challenge; the squad's side needs just its head and dot.
    private static func coachFace(in squad: SquadID, api: WildcardAPI, side: WidgetSide, at now: Date) async
        -> CoachRead
    {
        let hire: SquadCoach.Hire
        do {
            guard let hired = try await api.coach(of: squad).hire else { return .noCoach }
            hire = hired
        } catch {
            return .unreadable
        }
        let unseen = (try? await api.coachCards(in: squad).stack.isEmpty).map { !$0 } ?? false
        let speaker = CoachSpeaker(id: hire.coach.id, name: hire.coach.name)
        guard side == .coach else {
            return .face(CoachFace(coach: speaker, line: nil, hasNews: unseen, challenge: nil))
        }
        let activity = try? await api.coachActivity(of: squad)
        let challenge = (try? await api.todayChallenge(in: squad)) ?? nil
        return .face(
            CoachFace(
                squad: squad, coach: SidelineCoach(coach: speaker, note: activity?.note),
                morningNote: activity?.memberNote, challenge: challenge, hasNews: unseen, at: now))
    }
}
