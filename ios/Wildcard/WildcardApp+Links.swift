import CheckInUI
import Contracts
import DailyPushDomain
import HomeWidgetDomain
import SwiftUI

/// Where a tapped notification or home screen widget opens.
extension WildcardApp {
    /// A tapped notification: 今天, or where the 6pm push's view asked to go (动态, or 今天 with
    /// the check-in kinds open).
    static func open(_ destination: PushDestination?, today: TodayModel, tab: Binding<MainTabs.Tab>) {
        switch destination {
        case .feed:
            tab.wrappedValue = .feed
        case .checkIn:
            tab.wrappedValue = .today
            today.openCheckIn()
        case nil:
            tab.wrappedValue = .today
        }
    }

    /// Opens the place a home screen widget asked for: 今天, 打卡 over it, the 训练 page started
    /// from the workout the widget's capsule offered, or 出赛表, which `MainTabs` opens as a
    /// notice's place.
    static func open(
        _ link: WidgetLink, today: TodayModel, tab: Binding<MainTabs.Tab>, place: Binding<AppDestination?>
    ) {
        switch link {
        case .schedule:
            place.wrappedValue = .schedule
        case .today:
            open(nil, today: today, tab: tab)
        case .checkIn:
            open(.checkIn, today: today, tab: tab)
        case .postWorkout(let source):
            tab.wrappedValue = .today
            Task { await today.openCheckIn(posting: source) }
        }
    }

    /// A home screen widget's link, or a place in the app by its address (`wildcard://coach`).
    static func open(
        _ url: URL, today: TodayModel, tab: Binding<MainTabs.Tab>, place: Binding<AppDestination?>
    ) {
        if let link = WidgetLink(url: url) {
            open(link, today: today, tab: tab, place: place)
        } else if let destination = AppDestination(address: url.absoluteString) {
            place.wrappedValue = destination
        }
    }
}
