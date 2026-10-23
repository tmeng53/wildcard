import CheckInDomain
import CheckInUI
import Foundation
import UIKit

/// Launch arguments the UI tests pass in.
enum LaunchOptions {
    /// `-styleguide`: open the style guide instead of 今天.
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

    /// `-recap-missed`: the sample story where the squad fell short of its plans.
    static var recapMissed: Bool {
        ProcessInfo.processInfo.arguments.contains("-recap-missed")
    }

    /// `-uitest-recap-manual`: the story's pages move on only when tapped, so UI tests can
    /// screenshot each one on a slow simulator.
    static var recapManual: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-recap-manual")
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

    /// `-uitest-care`: a writer that reads every reason as self-harm, so UI tests can reach the
    /// care line before the AI writer exists.
    static var disclaimerWriter: any DisclaimerWriter {
        ProcessInfo.processInfo.arguments.contains("-uitest-care") ? CareWriter() : DiceDisclaimerWriter()
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
