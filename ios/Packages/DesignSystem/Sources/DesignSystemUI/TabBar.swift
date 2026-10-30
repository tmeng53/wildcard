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

/// The app's floating tab bar: an interactive Liquid Glass capsule over the scene, like the
/// system's, each tab an icon over its name. The selected tab sits on a see-through ink block, so
/// the glass shows through it too, in ink; the others are grey. It never takes
/// the scene's color. The caller places it `Sizing.tabBarBottom` above the screen's bottom edge
/// with page margins.
public struct TabBar<ID: Hashable>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let items: [TabBarItem<ID>]
    @Binding private var selection: ID

    public init(_ items: [TabBarItem<ID>], selection: Binding<ID>) {
        self.items = items
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                tab(item)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Space.xxs)
        .frame(height: Sizing.tabBar)
        .glassEffect(.regular.interactive(), in: Capsule())
        .haptic(.pick, trigger: selection)
    }

    /// How much ink the selected tab's block holds.
    private static var selectedOpacity: Double { 0.08 }

    private func tab(_ item: TabBarItem<ID>) -> some View {
        let isSelected = item.id == selection
        let shape = RoundedRectangle(
            cornerRadius: Radius.concentric(
                outer: Sizing.tabBar / 2, inset: (Sizing.tabBar - Sizing.tabItemHeight) / 2),
            style: .continuous)
        return Button {
            withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) { selection = item.id }
        } label: {
            VStack(spacing: Space.xxs / 2) {
                Image(systemName: item.systemImage)
                    .font(.system(size: Sizing.icon, weight: isSelected ? .semibold : .regular))
                    .frame(height: Sizing.icon + Space.xxs)
                    .accessibilityHidden(true)
                item.title
                    .typeStyle(isSelected ? TypeRamp.tabSelected : TypeRamp.tab)
                    .lineLimit(1)
            }
            .foregroundStyle(Color(role: isSelected ? .fgDefault : .fgMuted, in: theme))
            .frame(width: Sizing.tabItemWidth, height: Sizing.tabItemHeight)
            .background {
                if isSelected {
                    shape.fill(Color(role: .fgDefault, in: theme).opacity(Self.selectedOpacity))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(ifPresent: item.accessibilityIdentifier)
    }
}
#endif
