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
