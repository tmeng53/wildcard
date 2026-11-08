import Foundation

/// The sample squad's coach for the UI tests.
extension LaunchOptions {
    /// `-uitest-coach`: the sample squad has hired 毛头, who wrote today's 战术板 line, over its card
    /// opened from the home and pinned on 动态, and replied to three of its posts.
    static var sidelineCoach: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-coach")
    }

    /// `-uitest-coach-letter`: the sample squad changed from 毛头 to 帕帕, who was left 毛头's letter
    /// (交接信), not yet opened on this phone.
    static var coachLetter: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-coach-letter")
    }

    /// `-uitest-coach-note`: 毛头 also left me today's morning note (便条), waiting for me to open
    /// it from 毛头's phone, 通知 or its push.
    static var coachNote: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-coach-note")
    }
}
