import AvatarArt
import CheckInDomain
import CheckInUI
import Contracts
import DesignSystem
import Foundation
import NotificationsDomain
import NotificationsUI
import ScheduleUI
import SquadUI
import UIKit

/// Launch arguments the UI tests pass in.
enum LaunchOptions {
    /// `-styleguide`: open the style guide instead of 今天.
    /// `-loading`: the launch cover, which a fast launch never shows long enough to see.
    static var showsLoading: Bool {
        ProcessInfo.processInfo.arguments.contains("-loading")
    }

    /// `-health-sample`: Health connected, with the sample day of workouts; else not until 连接.
    static var healthSample: Bool {
        ProcessInfo.processInfo.arguments.contains("-health-sample")
    }

    static var showsStyleGuide: Bool {
        ProcessInfo.processInfo.arguments.contains("-styleguide")
    }

    /// `-recap`: open the 战报's entry tile and sample story instead of 今天.
    static var showsRecap: Bool {
        ProcessInfo.processInfo.arguments.contains("-recap")
    }

    /// `-recap-pending`: the sample story with its titles still waiting on the AI run.
    static var recapPending: Bool {
        ProcessInfo.processInfo.arguments.contains("-recap-pending")
    }

    /// `-recap-waiting`: the sample story with its titles on their way, before the AI run reached
    /// the squad (no try failed yet).
    static var recapWaiting: Bool {
        ProcessInfo.processInfo.arguments.contains("-recap-waiting")
    }

    /// `-recap-missed`: the sample story where the squad fell short of its plans.
    static var recapMissed: Bool {
        ProcessInfo.processInfo.arguments.contains("-recap-missed")
    }

    /// `-recap-picker`: the sample reader picks next week's scene, so the story's last page
    /// carries 冠军专属's sticker.
    static var recapPicker: Bool {
        ProcessInfo.processInfo.arguments.contains("-recap-picker")
    }

    /// `-recap-winter`: the 雪场 is open as well, so the sticker has six scenes and scrolls.
    static var recapWinter: Bool {
        ProcessInfo.processInfo.arguments.contains("-recap-winter")
    }

    /// `-recap-reveal pool 0.8`: open the sample story on its last page with the reveal of that
    /// scene held at that second, for UI tests' screenshots.
    static var recapReveal: (scene: SceneTheme, at: Double)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-recap-reveal"), flag + 2 < arguments.count,
            let scene = SceneTheme(rawValue: arguments[flag + 1]), let time = Double(arguments[flag + 2])
        else { return nil }
        return (scene, time)
    }

    /// `-uitest-recap-manual`: the story's pages move on only when tapped, so UI tests can
    /// screenshot each one on a slow simulator.
    static var recapManual: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-recap-manual")
    }

    /// `-tab me`: open on another tab than 今天 (`feed`, `me`, or `schedule` for 我 with 出赛表
    /// open; `squad` opens 今天 with 小队 open).
    static var firstTab: MainTabs.Tab {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-tab"), flag + 1 < arguments.count else { return .today }
        switch arguments[flag + 1] {
        case "feed": return .feed
        case "schedule": return .profile
        case "me": return .profile
        default: return .today
        }
    }

    /// `-tab squad`: 今天 opens on 小队.
    static var opensSquad: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-tab"), flag + 1 < arguments.count else { return false }
        return arguments[flag + 1] == "squad"
    }

    /// `-tab schedule`: 我 opens on 出赛表.
    static var opensSchedule: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-tab"), flag + 1 < arguments.count else { return false }
        return arguments[flag + 1] == "schedule"
    }

    /// `-widgets`: the home screen widgets on the sample squad, instead of the app.
    static var showsWidgets: Bool {
        ProcessInfo.processInfo.arguments.contains("-widgets")
    }

    /// `-daily-push full` (or `empty`): the 6pm push's long-press view on the sample squad, as
    /// its notification shows it, instead of the app.
    static var dailyPush: DailyPushPreview.Day? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-daily-push"), flag + 1 < arguments.count else { return nil }
        return DailyPushPreview.Day(rawValue: arguments[flag + 1])
    }

    /// `-uitest-me-fails`: the in-memory member refuses every change, so UI tests see a switch
    /// flip back and a delete fail.
    static var meFailsSaving: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-me-fails")
    }

    /// The sample member's 通知: the sample squad's last two weeks, or none with
    /// `-uitest-no-notices`, to see the page empty. `-uitest-broadcast trot|jingle` adds that
    /// holiday's pre-holiday broadcast, told just now, which 今天 shows on its celebration card,
    /// and `-uitest-broadcast thanks` a letter from the team, which flies in over 今天.
    /// `-uitest-live-comment` tells a teammate's comment live a few seconds after launch.
    static var notices: any NoticeSource {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uitest-no-notices") { return InMemoryNoticeSource.empty }
        if arguments.contains("-uitest-live-comment") { return InMemoryNoticeSource.withLiveComment(now: now()) }
        guard let flag = arguments.firstIndex(of: "-uitest-broadcast"), flag + 1 < arguments.count else {
            return InMemoryNoticeSource.sample(now: now())
        }
        let asked = arguments[flag + 1]
        let told = asked == "thanks" ? InMemoryNoticeSource.thanksLetter() : InMemoryNoticeSource.celebration(asked)
        return InMemoryNoticeSource.sample(now: now(), latest: [told])
    }

    /// `-uitest-offline-feed`: 动态 whose posts can't be read, as with no server.
    static var feedIsOffline: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-offline-feed")
    }

    /// `-uitest-empty-feed`: 动态 with no posts, to see its empty scene.
    static var showsEmptyFeed: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-empty-feed")
    }

    /// `-squad-seat winner`: who the member is on the in-memory squad's 小队设置 (`captain`,
    /// `winner`, `member`, `noWinner`, `coached` for the captain of a squad with a coach,
    /// `coachedMember` for a mate in it); the captain by default, of a squad with a coach under
    /// `-uitest-coach` or `-uitest-coach-note`, so the coach on the home opens its page.
    static var squadSeat: InMemorySquadSettingsService.Seat {
        let arguments = ProcessInfo.processInfo.arguments
        let fallback: InMemorySquadSettingsService.Seat = sidelineCoach || coachNote ? .coached : .captain
        guard let flag = arguments.firstIndex(of: "-squad-seat"), flag + 1 < arguments.count else { return fallback }
        return InMemorySquadSettingsService.Seat(rawValue: arguments[flag + 1]) ?? fallback
    }

    /// `-uitest-long-names`: the in-memory squad's names are as long as the rules allow.
    static var longNames: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-long-names")
    }

    /// `-uitest-hold-offers`: 出赛表's 也改到模板 stays a minute, not 5 seconds, so a slow
    /// simulator still finds it before it goes by itself.
    static var templateOfferHold: Duration {
        ProcessInfo.processInfo.arguments.contains("-uitest-hold-offers") ? .seconds(60) : .seconds(5)
    }

    /// `-uitest-no-push`: never show the notification prompt, which would cover the screens UI
    /// tests check after a post. Only the notification UI test leaves it out.
    static var asksForNotifications: Bool {
        !ProcessInfo.processInfo.arguments.contains("-uitest-no-push")
    }

    #if DEBUG
    /// `-local-backend`: use local Supabase and the API on this Mac (`scripts/local-backend.sh`)
    /// instead of the sample squad.
    static var usesLocalBackend: Bool {
        ProcessInfo.processInfo.arguments.contains("-local-backend")
    }

    /// `-test-member EMAIL PASSWORD`: sign in as this member of local Supabase instead of with
    /// Apple, which the simulator can't do without the team's signing (`scripts/local-backend.sh`
    /// makes `member1@wildcard.test` to `member3@…`).
    static var testMember: (email: String, password: String)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-test-member"), flag + 2 < arguments.count else { return nil }
        return (arguments[flag + 1], arguments[flag + 2])
    }

    /// `-uitest-push JSON`: an APNs payload (one of `WildcardUITests/push-samples.json`, which the
    /// API writes) that the app shows as a notification a few seconds after launch, so a UI test
    /// can look at its banner and tap it.
    static var pushSample: [String: Any]? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uitest-push"), flag + 1 < arguments.count else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(arguments[flag + 1].utf8))) as? [String: Any]
    }
    #endif

    /// With `-onboarding`, `-slow-sign-in`: signing in on the open screen takes this long, in
    /// seconds, so the loader that covers a slow sign-in shows.
    static var signInWait: Double? {
        ProcessInfo.processInfo.arguments.contains("-slow-sign-in") ? 2 : nil
    }

    /// On the sample squad, `-onboarding`: open sign-up, then 今天 once it is done.
    static var showsOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("-onboarding") || rejoins
    }

    /// The moment sign-up starts at: noon on this week's Monday with `-uitest-monday`, so the
    /// week step's default plan and screenshots don't change with the day the tests run;
    /// otherwise now.
    static var signUpTime: Date {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-monday") else { return .now }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        guard let monday = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return .now }
        return calendar.date(byAdding: .hour, value: 12, to: monday) ?? .now
    }

    /// `-uitest-squad N`: the sample squad with N members, me included (1 to 8; 8 without it), so
    /// UI tests can check the scene at every size.
    static var squadSize: Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uitest-squad"), flag + 1 < arguments.count,
            let size = Int(arguments[flag + 1])
        else { return 8 }
        return size
    }

    /// `-uitest-patted`: on the sample squad, 小米 and 阿杰 patted me an hour ago, so the home
    /// plays their pats on opening. It plays on every launch: what was shown is kept apart from
    /// the app's own settings and forgotten each time.
    static var pattedMe: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-patted")
    }

    /// `-uitest-bubble-hold`: a pat's bubble, a notice on 今天 and 商店街's 「已放进衣橱」 stay up
    /// for a minute instead of a few seconds, so a UI test checks them without racing their timers.
    static var bubbleHold: Double? {
        ProcessInfo.processInfo.arguments.contains("-uitest-bubble-hold") ? 60 : nil
    }

    /// `-uitest-together wave|stack|bump`: the sample squad's home opens on that celebration
    /// (人浪, 叠罗汉, 撞头). Without it the sample squad never celebrates together, so other UI
    /// tests meet a home that holds still.
    static var together: SquadCelebration.Kind? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uitest-together"), flag + 1 < arguments.count else { return nil }
        return SquadCelebration.Kind(rawValue: arguments[flag + 1])
    }

    /// `-uitest-meals`: two of the sample squad's latest posts are meals (小米's salad after her
    /// run, Leo's boba), so they eat on the home and their bubbles say so.
    static var meals: Bool { ProcessInfo.processInfo.arguments.contains("-uitest-meals") }

    /// Apple Health's sample day starts afresh on each launch: nothing put away from the home's
    /// card, every number shared.
    static var healthDefaults: UserDefaults {
        let suite = "uitest-health"
        guard healthSample, let defaults = UserDefaults(suiteName: suite) else { return todayDefaults }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Where 今天 keeps what it has shown: the app's settings, or with `-uitest-patted`,
    /// `-uitest-coach` or `-uitest-together` a suite emptied at launch.
    static var todayDefaults: UserDefaults {
        let suite = "uitest-today"
        guard pattedMe || sidelineCoach || coachNote || together != nil, let defaults = UserDefaults(suiteName: suite)
        else {
            return .standard
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// `-uitest-scene track`: the sample squad's home on another scene than the gym.
    static var scene: SceneTheme {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uitest-scene"), flag + 1 < arguments.count,
            let scene = SceneTheme(rawValue: arguments[flag + 1])
        else { return .gym }
        return scene
    }

    /// `-uitest-scene-moved track`: a teammate moves the sample squad to that scene once 今天
    /// is up, so UI tests see the drop and its notice.
    static var sceneMoved: SceneTheme? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uitest-scene-moved"), flag + 1 < arguments.count else { return nil }
        return SceneTheme(rawValue: arguments[flag + 1])
    }

    /// `-uitest-unlocked`: the sample member's training has just opened DEUCE CLUB, which 今天
    /// tells once it is up and 我's editor has open, so UI tests see the notice and its tap.
    /// `-uitest-unlocked-piece`: WARM-UP's headphones have just come in instead, which 今天 tells as
    /// 「热身社 到新货了」 and whose tap opens the store, the headphones wearing NEW on its rack.
    static var unlocked: [Unlock] {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uitest-unlocked-piece") {
            return [Unlock(kind: .piece, id: "warmup-headphones", unlockedAt: now(), sports: [], checkIns: 2)]
        }
        guard arguments.contains("-uitest-unlocked") else { return [] }
        return [Unlock(kind: .store, id: "deuce", unlockedAt: now(), sports: ["tennis"], checkIns: 3)]
    }

    /// `-uitest-care`: a writer that reads every reason as self-harm, so UI tests can reach the
    /// care line before the AI writer exists.
    static var disclaimerWriter: any DisclaimerWriter {
        ProcessInfo.processInfo.arguments.contains("-uitest-care") ? CareWriter() : DiceDisclaimerWriter()
    }

    /// `-uitest-noon`: the clock starts at noon today and runs on from there, so the scene is in
    /// daylight and the squad cheers whatever time CI runs the UI tests. `-uitest-evening` starts
    /// it at 21:30 instead, when 今日赛况 is on the card, and `-uitest-night` at 23:30, when the
    /// squad sleeps and the light cord hangs under the card; each wins over `-uitest-noon`.
    static let now: @Sendable () -> Date = {
        let arguments = ProcessInfo.processInfo.arguments
        let start: (hour: Int, minute: Int)? =
            arguments.contains("-uitest-night")
            ? (23, 30)
            : arguments.contains("-uitest-evening") ? (21, 30) : arguments.contains("-uitest-noon") ? (12, 0) : nil
        guard let start,
            let started = Calendar.current.date(
                bySettingHour: start.hour, minute: start.minute, second: 0, of: Date())
        else { return { Date() } }
        let launched = Date()
        return { started.addingTimeInterval(Date().timeIntervalSince(launched)) }
    }()

    /// UI tests' flags that make 今天 forget what this phone kept, so each test starts as a member
    /// first sees it and can still change it (passing the key itself would pin it: launch arguments
    /// win over what the app writes): `-uitest-recap-unseen`, which day's 今日赛况 was opened;
    /// `-uitest-night`, the lights switched on; `-uitest-card-folded`, home's card left open and
    /// the page it was left on.
    static func forgetTodayStateIfAsked() {
        let arguments = ProcessInfo.processInfo.arguments
        let kept = [
            "-uitest-recap-unseen": ["today.recapSeen"], "-uitest-night": ["today.lightsOn"],
            "-uitest-card-folded": ["today.cardCollapsed", "today.cardPage"],
        ]
        for (flag, keys) in kept where arguments.contains(flag) {
            for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    /// `-uitest-thursday`: 出赛表's clock starts at noon on this week's Thursday and runs on, so
    /// this week has days behind and ahead whatever day CI runs the UI tests.
    static let scheduleNow: @Sendable () -> Date = {
        let calendar = Calendar.current
        guard ProcessInfo.processInfo.arguments.contains("-uitest-thursday"),
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())
        else { return now }
        // Monday is 2 in the Gregorian calendar, Sunday 1; weeks here run Monday to Sunday.
        let mondayFirst = (calendar.component(.weekday, from: noon) + 5) % 7
        let thursday = noon.addingTimeInterval(Double(3 - mondayFirst) * 86_400)
        let launched = Date()
        return { thursday.addingTimeInterval(Date().timeIntervalSince(launched)) }
    }()

    /// `-uitest-photos N`: hand N generated photos to every check-in instead of the system photo
    /// picker, which UI tests can't drive reliably.
    static var photoSource: PhotoSource {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uitest-photos"), flag + 1 < arguments.count,
            let count = Int(arguments[flag + 1]), count > 0
        else { return .library }
        return .provided((0..<count).compactMap(samplePhoto))
    }

    /// A plain colored square with a few stripes, so the cover and thumbnails tell apart.
    private static func samplePhoto(_ index: Int) -> PreparedPhoto? {
        let colors: [UIColor] = [.systemTeal, .systemIndigo, .systemOrange]
        let size = CGSize(width: 900, height: 1200)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            colors[index % colors.count].setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.25).setFill()
            for stripe in 0...index {
                context.fill(CGRect(x: 0, y: 160 + Double(stripe) * 220, width: size.width, height: 80))
            }
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.7), let pixels = image.cgImage else { return nil }
        return PreparedPhoto(id: UUID(), jpeg: jpeg, size: try? PhotoSize(width: pixels.width, height: pixels.height))
    }
}

/// Blocks every reason (`-uitest-care`).
private struct CareWriter: DisclaimerWriter {
    func suggestions(for reason: String, style: DisclaimerStyle) async -> DisclaimerSuggestions {
        .blocked
    }
}
