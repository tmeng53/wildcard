#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// One choice in a glass menu (`glassMenu(isPresented:title:items:)`): an icon and a few words, red
/// when it can't be taken back. With a `confirmation`, picking it asks first: the menu's rows give
/// way to the question in place, then the confirming row and 取消.
public struct GlassMenuItem: Identifiable {
    public enum Role: Sendable {
        case standard
        /// Words and icon in `fgDanger`, in their own group at the bottom of the menu.
        case destructive
    }

    /// The question a pick asks before it acts (把 Mia 移出小队？), and the row that answers it.
    public struct Confirmation {
        let question: Text
        let message: Text?
        let label: Text
        let id: String

        /// `label` is the confirming row's words (移出); `id` its UI-test identifier.
        public init(_ question: Text, message: Text? = nil, label: Text, id: String) {
            self.question = question
            self.message = message
            self.label = label
            self.id = id
        }
    }

    /// The row's UI-test identifier, unique in its menu.
    public let id: String
    /// The row's words; also the name of its VoiceOver action where the source offers one.
    public let title: Text
    let systemImage: String?
    let role: Role
    let isSelected: Bool
    let confirmation: Confirmation?
    public let action: @MainActor () -> Void

    /// `isSelected` ticks the row (the language spoken now).
    public init(
        _ title: Text, systemImage: String? = nil, role: Role = .standard, isSelected: Bool = false, id: String,
        confirm confirmation: Confirmation? = nil, action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isSelected = isSelected
        self.id = id
        self.confirmation = confirmation
        self.action = action
    }
}

extension View {
    /// The app's one menu (approved 2026-11-04): a Liquid Glass panel growing out of this view, for
    /// a 「···」 button, a long-press or a row that asks before acting. Rows are 48 points, an
    /// icon and a label; destructive ones go last in their own group. A tap outside closes it;
    /// a pick closes it and acts, or asks first when the item has a `confirmation`.
    public func glassMenu(isPresented: Binding<Bool>, title: Text? = nil, items: [GlassMenuItem]) -> some View {
        popover(isPresented: isPresented) {
            GlassMenu(title: title, items: items, confirming: nil) { isPresented.wrappedValue = false }
                .presentationCompactAdaptation(.popover)
        }
    }

    /// A glass menu that opens on its question (退出登录？): `item`'s confirmation, its confirming
    /// row and 取消. For a row or button that is already the first step.
    public func glassConfirm(isPresented: Binding<Bool>, _ item: GlassMenuItem) -> some View {
        popover(isPresented: isPresented) {
            GlassMenu(title: nil, items: [item], confirming: item.id) { isPresented.wrappedValue = false }
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The panel: the system's popover, which on iOS 26 is Liquid Glass and grows from its source,
/// holding our rows.
struct GlassMenu: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let title: Text?
    private let items: [GlassMenuItem]
    private let close: () -> Void
    @State private var confirming: GlassMenuItem.ID?
    /// The picked action, run once the panel is gone, so one that presents a sheet or a full-screen
    /// page doesn't race the popover's dismissal.
    @State private var picked: (@MainActor () -> Void)?

    static let width: Double = 240
    /// Between the panel's edge and its rows' pressed pill.
    static let inset: Double = 6

    init(title: Text?, items: [GlassMenuItem], confirming: GlassMenuItem.ID?, close: @escaping () -> Void) {
        self.title = title
        self.items = items
        self.close = close
        _confirming = State(initialValue: confirming)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = items.first(where: { $0.id == confirming }), let confirmation = item.confirmation {
                header(confirmation.question, message: confirmation.message)
                GlassMenuRow(confirmation.label, systemImage: item.systemImage, role: item.role, isEmphasized: true) {
                    pick(item)
                }
                .accessibilityIdentifier(confirmation.id)
                groupGap
                GlassMenuRow(Text(copy: "取消", bundle: .module), action: close)
                    .accessibilityIdentifier("glassMenu.cancel")
            } else {
                if let title { header(title, message: nil) }
                let standard = items.filter { $0.role == .standard }
                let destructive = items.filter { $0.role == .destructive }
                ForEach(standard) { row($0) }
                if !standard.isEmpty, !destructive.isEmpty { groupGap }
                ForEach(destructive) { row($0) }
            }
        }
        .padding(.vertical, Self.inset)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: confirming)
        .onDisappear {
            picked?()
            picked = nil
        }
    }

    private func pick(_ item: GlassMenuItem) {
        picked = item.action
        close()
    }

    private func row(_ item: GlassMenuItem) -> some View {
        GlassMenuRow(item.title, systemImage: item.systemImage, role: item.role, isSelected: item.isSelected) {
            if item.confirmation != nil {
                confirming = item.id
            } else {
                pick(item)
            }
        }
        .accessibilityIdentifier(item.id)
    }

    private func header(_ question: Text, message: Text?) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            question
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            if let message {
                message
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Space.m)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The band between groups: the standard rows, then the destructive ones (or 取消).
    private var groupGap: some View {
        Rectangle()
            .fill(Color(role: .fgDefault, in: theme).opacity(Self.gapOpacity))
            .frame(height: Space.xs)
            .padding(.vertical, Space.xxs / 2)
            .accessibilityHidden(true)
    }

    private static let gapOpacity = 0.05
}

/// A row of the glass menu: icon, words and, when picked, a tick.
struct GlassMenuRow: View {
    @Environment(\.sceneTheme) private var theme
    private let title: Text
    private let systemImage: String?
    private let role: GlassMenuItem.Role
    private let isSelected: Bool
    private let isEmphasized: Bool
    private let action: @MainActor () -> Void

    static let height: Double = 48

    init(
        _ title: Text, systemImage: String? = nil, role: GlassMenuItem.Role = .standard, isSelected: Bool = false,
        isEmphasized: Bool = false, action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isSelected = isSelected
        self.isEmphasized = isEmphasized
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Sizing.icon - 3, weight: .medium))
                        .frame(width: Sizing.icon)
                        .accessibilityHidden(true)
                }
                // Wraps rather than cut off at large text sizes; the row grows from 48.
                title
                    .typeStyle(isEmphasized ? TypeRamp.headline : TypeRamp.body)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.m)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: Sizing.smallIcon, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color(role: role == .destructive ? .fgDanger : .fgDefault, in: theme))
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassMenuRowStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// While a row is held: a faint ink pill, concentric with the panel.
private struct GlassMenuRowStyle: ButtonStyle {
    @Environment(\.sceneTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(
                    cornerRadius: Radius.concentric(outer: Radius.menu, inset: GlassMenu.inset), style: .continuous
                )
                .fill(Color(role: .fgDefault, in: theme).opacity(configuration.isPressed ? Self.pressedOpacity : 0))
                .padding(.horizontal, GlassMenu.inset)
            }
    }

    private static let pressedOpacity = 0.06
}
#endif
