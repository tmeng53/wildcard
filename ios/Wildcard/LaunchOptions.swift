import CheckInDomain
import CheckInUI
import DesignSystem
import Foundation
import ScheduleUI
import UIKit

/// Launch arguments the UI tests pass in.
enum LaunchOptions {
    /// `-styleguide`: open the style guide instead of 今天.
    static var showsStyleGuide: Bool {
        ProcessInfo.processInfo.arguments.contains("-styleguide")
    }

    /// `-tab me`: open on another tab than 今天 (`feed`, `schedule`, `me`).
    static var firstTab: MainTabs.Tab {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-tab"), flag + 1 < arguments.count else { return .today }
        switch arguments[flag + 1] {
        case "feed": return .feed
        case "schedule": return .schedule
        case "me": return .profile
        default: return .today
        }
    }

    /// `-uitest-me-fails`: the in-memory member refuses every change, so UI tests see a switch
    /// flip back and a delete fail.
    static var meFailsSaving: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-me-fails")
    }

    /// `-uitest-empty-feed`: 动态 with no posts, to see its empty scene.
    static var showsEmptyFeed: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-empty-feed")
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
    #endif

    /// On the sample squad, `-onboarding`: open sign-up, then 今天 once it is done.
    static var showsOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("-onboarding")
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

    /// `-uitest-scene track`: the sample squad's home on another scene than the gym.
    static var scene: SceneTheme {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uitest-scene"), flag + 1 < arguments.count,
            let scene = SceneTheme(rawValue: arguments[flag + 1])
        else { return .gym }
        return scene
    }

    /// `-uitest-care`: a writer that reads every reason as self-harm, so UI tests can reach the
    /// care line before the AI writer exists.
    static var disclaimerWriter: any DisclaimerWriter {
        ProcessInfo.processInfo.arguments.contains("-uitest-care") ? CareWriter() : DiceDisclaimerWriter()
    }

    /// `-uitest-save-poster`: 存图 says it saved without asking for Photos, whose permission prompt
    /// UI tests can't answer.
    static var posterSaver: any PosterSaver {
        ProcessInfo.processInfo.arguments.contains("-uitest-save-poster") ? PretendPosterSaver() : PhotoLibrarySaver()
    }

    /// `-uitest-noon`: the clock starts at noon today and runs on from there, so the scene is in
    /// daylight and the squad cheers whatever time CI runs the UI tests.
    static let now: @Sendable () -> Date = {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-noon"),
            let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())
        else { return { Date() } }
        let launched = Date()
        return { noon.addingTimeInterval(Date().timeIntervalSince(launched)) }
    }()

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
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else { return nil }
        return PreparedPhoto(id: UUID(), jpeg: jpeg)
    }
}

/// Blocks every reason (`-uitest-care`).
private struct CareWriter: DisclaimerWriter {
    func suggestions(for reason: String, style: DisclaimerStyle) async -> DisclaimerSuggestions {
        .blocked
    }
}
