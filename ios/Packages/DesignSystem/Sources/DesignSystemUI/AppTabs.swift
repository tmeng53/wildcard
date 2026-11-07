#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

#if os(iOS)
import UIKit
#endif

/// One tab: its name and SF Symbol.
public struct TabBarItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: Text
    public let systemImage: String
    public let accessibilityIdentifier: String?

    public init(id: ID, title: Text, systemImage: String, accessibilityIdentifier: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

/// The app's tabs in the system's own tab bar, so it is iOS's Liquid Glass bar: floating over
/// the screens, the selected tab on its glass lens, morphing as it moves. The selected tab is
/// ink, never the scene's color; the screens inside keep the system's tint. Each screen keeps to
/// its safe area, which the system raises above the bar, so none of them measures the bar.
/// `showsBar` false hides the bar (a tab's full-screen step). A tab in `dotted` carries a small
/// brand dot, no number: something new there since the member last looked. `backToRoot` is
/// called with the tab left and with the open tab tapped again, for it to close the pages pushed
/// over it, as iOS's own apps do, so every tab opens from the bar on its own page.
public struct AppTabs<ID: Hashable, Content: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let items: [TabBarItem<ID>]
    @Binding private var selection: ID
    private let showsBar: Bool
    private let dotted: Set<ID>
    private let backToRoot: (ID) -> Void
    private let content: (ID) -> Content

    public init(
        _ items: [TabBarItem<ID>], selection: Binding<ID>, showsBar: Bool = true, dotted: Set<ID> = [],
        backToRoot: @escaping (ID) -> Void = { _ in },
        @ViewBuilder content: @escaping (ID) -> Content
    ) {
        self.items = items
        _selection = selection
        self.showsBar = showsBar
        self.dotted = dotted
        self.backToRoot = backToRoot
        self.content = content
        Self.paintDots()
    }

    /// The selection as the bar sets it: a tap on the tab already open is a reselection, which
    /// the system also reports through the binding.
    private var tapped: Binding<ID> {
        Binding(
            get: { selection },
            set: { tab in
                if tab == selection { backToRoot(tab) } else { selection = tab }
            })
    }

    /// The system draws a badge red; ours is the brand's graphite, never an alarm.
    private static func paintDots() {
        #if os(iOS)
        UITabBarItem.appearance().badgeColor = UIColor(Color(role: .bgBrand, in: .gym))
        #endif
    }

    public var body: some View {
        TabView(selection: tapped) {
            ForEach(items) { item in
                Tab(value: item.id) {
                    content(item.id)
                        // Back to the system's tint inside: only the bar's selected tab is ink.
                        .tint(Color?.none)
                        .modifier(TabBarVisibility(isVisible: showsBar))
                } label: {
                    Label {
                        item.title
                    } icon: {
                        Image(systemName: item.systemImage)
                    }
                }
                // An empty badge is the system's dot, without a number.
                .badge(dotted.contains(item.id) ? Text(verbatim: "") : nil)
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
            }
        }
        .tint(Color(role: .fgDefault, in: theme))
        .haptic(.pick, trigger: selection)
        .onChange(of: selection) { left, _ in backToRoot(left) }
    }
}

/// Shows or hides the system tab bar over a tab's screen; the bar exists on iOS only (the
/// package also builds for the Mac host its tests run on).
private struct TabBarVisibility: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        // Automatic, not visible, so a page pushed inside can still put the bar away
        // (`pushedPage(hidesTabBar:)`).
        content.toolbarVisibility(isVisible ? .automatic : .hidden, for: .tabBar)
        #else
        content
        #endif
    }
}
#endif
