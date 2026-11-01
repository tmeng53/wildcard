#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

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
/// `showsBar` false hides the bar (a tab's full-screen step).
public struct AppTabs<ID: Hashable, Content: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let items: [TabBarItem<ID>]
    @Binding private var selection: ID
    private let showsBar: Bool
    private let content: (ID) -> Content

    public init(
        _ items: [TabBarItem<ID>], selection: Binding<ID>, showsBar: Bool = true,
        @ViewBuilder content: @escaping (ID) -> Content
    ) {
        self.items = items
        _selection = selection
        self.showsBar = showsBar
        self.content = content
    }

    public var body: some View {
        TabView(selection: $selection) {
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
                .accessibilityIdentifier(item.accessibilityIdentifier ?? "")
            }
        }
        .tint(Color(role: .fgDefault, in: theme))
        .haptic(.pick, trigger: selection)
    }
}

/// Shows or hides the system tab bar over a tab's screen; the bar exists on iOS only (the
/// package also builds for the Mac host its tests run on).
private struct TabBarVisibility: ViewModifier {
    let isVisible: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbarVisibility(isVisible ? .visible : .hidden, for: .tabBar)
        #else
        content
        #endif
    }
}
#endif
