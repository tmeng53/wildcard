#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The reaction bar's measures, for callers that place it or fly an emoji from one of its slots.
public enum ReactionBarMetrics {
    public static let height: Double = 52
    public static let inset = Space.xxs
    static let emojiSize: Double = 28
    static let hoverScale: Double = 1.3
    static let hoverRise: Double = 6
    static let slotStagger: Double = 0.015

    /// The bar's width for `count` emoji and ＋, each a tap target wide, inside its ends.
    public static func width(count: Int) -> Double {
        Double(count + 1) * Sizing.minimumTapTarget + 2 * inset
    }

    /// Where slot `index` sits in a bar laid out at `bar`.
    public static func slotCenter(_ index: Int, in bar: CGRect) -> CGPoint {
        CGPoint(x: bar.minX + inset + (Double(index) + 0.5) * Sizing.minimumTapTarget, y: bar.midY)
    }
}

/// Picking a reaction (动态, the 6pm push): the quick emoji and ＋ in a glass
/// capsule over the post. Mine sits on a grey circle; picking it again takes it back. The slot
/// under a finger sliding along it (`hovered`) grows. Its emoji pop in one after another.
/// Each emoji's identifier is `identifier` + `.` + the emoji; ＋'s is `identifier.more`.
public struct ReactionBar<Item: Hashable>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let items: [Item]
    private let text: (Item) -> String
    private let mine: Item?
    private let hovered: Int?
    private let identifier: String
    private let pick: (Int) -> Void
    private let more: () -> Void
    @State private var shown = false

    public init(
        _ items: [Item], text: @escaping (Item) -> String, mine: Item?, hovered: Int? = nil, identifier: String,
        pick: @escaping (Int) -> Void, more: @escaping () -> Void
    ) {
        self.items = items
        self.text = text
        self.mine = mine
        self.hovered = hovered
        self.identifier = identifier
        self.pick = pick
        self.more = more
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                slot(item, at: index)
            }
            Button(action: more) {
                Image(systemName: "plus")
                    .font(.system(size: Sizing.smallIcon, weight: .semibold))
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(width: Sizing.compactControl, height: Sizing.compactControl)
                    .background(Color(role: .bgSubtle, in: theme), in: Circle())
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("更多表情", bundle: .module))
            .accessibilityIdentifier("\(identifier).more")
        }
        .padding(.horizontal, ReactionBarMetrics.inset)
        .frame(height: ReactionBarMetrics.height)
        .glassEffect(.regular, in: Capsule())
        .onAppear { shown = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("选一个回应", bundle: .module))
    }

    private func slot(_ item: Item, at index: Int) -> some View {
        let isHovered = hovered == index
        return Button {
            pick(index)
        } label: {
            Text(verbatim: text(item))
                .font(.system(size: ReactionBarMetrics.emojiSize))
                .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                .background {
                    if item == mine { Circle().fill(Color(role: .bgSubtle, in: theme)) }
                }
                .scaleEffect(isHovered ? ReactionBarMetrics.hoverScale : (shown || reduceMotion ? 1 : 0.4))
                .offset(y: isHovered ? -ReactionBarMetrics.hoverRise : 0)
                .opacity(shown || reduceMotion ? 1 : 0)
                .animation(
                    .wildcard(Motion.sheet, reduceMotion: reduceMotion)
                        .delay(Double(index) * ReactionBarMetrics.slotStagger),
                    value: shown
                )
                .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: isHovered)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(verbatim: text(item)))
        .accessibilityAddTraits(item == mine ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(text(item))")
    }
}

/// Any emoji, in glass, after ＋: the ones picked lately and all of them, with a search by name
/// where the surface has a keyboard. The caller sets its size. Each emoji's identifier is
/// `identifier` + `.` + the emoji.
public struct EmojiPicker<Item: Hashable>: View {
    @Environment(\.sceneTheme) private var theme
    private let recent: [Item]
    private let all: [Item]
    private let search: ((String) -> [Item])?
    private let text: (Item) -> String
    private let mine: Item?
    private let identifier: String
    private let pick: (Item) -> Void
    @State private var showsAll = false
    @State private var query = ""

    private static var cell: Double { 40 }
    private static var emojiSize: Double { 28 }

    public init(
        recent: [Item], all: [Item], search: ((String) -> [Item])? = nil, text: @escaping (Item) -> String,
        mine: Item? = nil, identifier: String, pick: @escaping (Item) -> Void
    ) {
        self.recent = recent
        self.all = all
        self.search = search
        self.text = text
        self.mine = mine
        self.identifier = identifier
        self.pick = pick
    }

    public var body: some View {
        let showsRecent = !showsAll && !recent.isEmpty
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                PickPill(Text("最近", bundle: .module), isSelected: showsRecent) { showsAll = false }
                PickPill(Text("全部", bundle: .module), isSelected: !showsRecent) { showsAll = true }
            }
            if !showsRecent, search != nil {
                SearchField(text: $query, prompt: Text("搜索表情", bundle: .module))
            }
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.cell, maximum: Self.cell), spacing: 0)], spacing: 0
                ) {
                    ForEach(shown(recent: showsRecent), id: \.self) { item in
                        cell(item)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(Space.s)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("全部表情", bundle: .module))
    }

    private func shown(recent showsRecent: Bool) -> [Item] {
        if showsRecent { return recent }
        if let search { return search(query) }
        return all
    }

    private func cell(_ item: Item) -> some View {
        Button {
            pick(item)
        } label: {
            Text(verbatim: text(item))
                .font(.system(size: Self.emojiSize))
                .frame(width: Self.cell, height: Self.cell)
                .background {
                    if item == mine { Circle().fill(Color(role: .bgSubtle, in: theme)) }
                }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(verbatim: text(item)))
        .accessibilityAddTraits(item == mine ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(text(item))")
    }
}
#endif
