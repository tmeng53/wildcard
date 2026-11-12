import Foundation
import HomeWidgetDomain

extension LaunchOptions {
    /// `-widget-link <url>`: the app opens as a tap on a home screen widget with that
    /// `wildcard://widget/…` link opens it from cold, the link held until the tabs are up, so UI
    /// tests reach the widget's place without the system's URL handling.
    static var widgetLink: WidgetLink? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-widget-link"), flag + 1 < arguments.count,
            let url = URL(string: arguments[flag + 1])
        else { return nil }
        return WidgetLink(url: url)
    }
}
