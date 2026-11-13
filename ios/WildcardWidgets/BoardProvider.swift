import AppIntents
import Backend
import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation
import HealthDomain
import HealthUI
import HomeWidgetDomain
import HomeWidgetUI
import SportsUI
import WidgetKit

/// One moment of a widget: the board then, or why there is none, and whether it was set to show
/// 本周出赛表.
struct BoardEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
    var showsSchedule = false
}

/// Reads the squad for the widgets: the home over our API, signed in with the app's shared
/// session, or the copy the widget kept when the network fails, and today's workouts in Apple
/// Health for the 打卡 capsule. The app also asks the widgets to read again whenever it leaves
/// the screen, so a post shows at once.
struct BoardProvider<Intent: BoardIntent>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        Self.sample(at: Date())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> BoardEntry {
        var entry = context.isPreview ? Self.sample(at: Date()) : await Self.read(at: Date()).entry
        entry.showsSchedule = configuration.showsSchedule
        return entry
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<BoardEntry> {
        let read = await Self.read(at: Date())
        var entry = read.entry
        entry.showsSchedule = configuration.showsSchedule
        let next =
            entry.state == .unavailable
            ? entry.date.addingTimeInterval(WidgetState.retryInterval)
            : WidgetBoard.nextLook(after: entry.date, in: read.zone)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private static func sample(at now: Date) -> BoardEntry {
        BoardEntry(date: now, state: .board(SampleBoard.board(on: LocalDay(at: now, in: .current))))
    }

    /// The board now, with the clock its day turns on.
    static func read(at now: Date) async -> (entry: BoardEntry, zone: TimeZone) {
        // The language picked in the app, and the sports' icons from the list this build ships.
        AppLanguage.adopt(from: AppGroup.defaults, folder: AppGroup.directory)
        SportList.shared.show(CatalogClient.bundled.sports)
        // The lines put over the String Catalog, as the app last kept them.
        if let copy = SharedCopy.inAppGroup?.read() { AppCopyLines.install(copy) }
        let entry = { (state: WidgetState) in (BoardEntry(date: now, state: state), TimeZone.current) }
        let session: WidgetSession
        switch await WidgetSession.open() {
        case .signedIn(let opened): session = opened
        // A build that names no backend (Debug) runs on the sample squad, as the app does.
        case .sample: return (sample(at: now), .current)
        // The Keychain is locked until the phone's first unlock after a restart, and so is the
        // widget's copy: try again soon, keeping the copy, rather than say nobody signed in.
        case .locked: return entry(.unavailable)
        // Nobody signed in: the copy goes with them.
        case .signedOut:
            WidgetSession.folders.forgetAll()
            return entry(.signedOut)
        }
        let backend = session.backend
        let home: Home
        // The copy kept on the phone may be from before a post, so only a fresh home offers a
        // workout to post, as 今天's card waits for the server's.
        var health = HealthRead()
        do {
            guard let read = try await backend.home() else { return entry(.noSquad) }
            home = read
            health = await HealthRead.now()
        } catch .signedOut {
            // The session can't be renewed any more.
            WidgetSession.folders.forgetAll()
            return entry(.signedOut)
        } catch {
            guard let saved = await backend.savedHome() else { return entry(.unavailable) }
            home = saved
        }
        let coach = try? await backend.coach(in: home.squad.id)
        let hasNews =
            coach == nil ? false : (try? await backend.newestUnseenCoachCard(in: home.squad.id)) != nil
        let board = WidgetBoard(
            home: home, day: LocalDay(at: now, in: home.timeZone), coach: coach?.coach.id, coachHasNews: hasNews,
            health: health.workouts, putAway: health.putAway)
        return (BoardEntry(date: now, state: .board(board)), home.timeZone)
    }
}

/// Today's workouts in Apple Health and which were put away from 今天's card, as the app keeps
/// them in the app group. Empty while Health isn't connected, or the phone is locked, when
/// HealthKit reads nothing. The widgets read the numbers alone, which is all the capsule shows;
/// the app reads the route and series once its 打卡 opens the 训练 page. It never asks for Health
/// access, which only the app can.
struct HealthRead {
    var workouts: [ImportedWorkout] = []
    var putAway: Set<WorkoutSource> = []

    @MainActor static func now() async -> HealthRead {
        guard let defaults = AppGroup.defaults else { return HealthRead() }
        let library = HealthKitLibrary(defaults: defaults, detail: .numbers, asksForNewTypes: false)
        let health = HealthConnection(library: library, defaults: defaults)
        await health.refresh()
        return HealthRead(workouts: health.recent, putAway: health.putAway)
    }
}
