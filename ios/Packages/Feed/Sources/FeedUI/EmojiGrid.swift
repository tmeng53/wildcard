#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// Any emoji, in glass: the ones picked lately, or all of them with a search by name.
struct EmojiGrid: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let pick: (Emoji) -> Void
    @State private var showsAll = false
    @State private var query = ""

    static let size = CGSize(width: 320, height: 340)
    private static let cell: Double = 40
    private static let emojiSize: Double = 28

    var body: some View {
        let showsRecent = !showsAll && !model.recent.isEmpty
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                PickPill(Text("最近", bundle: .module), isSelected: showsRecent) { showsAll = false }
                PickPill(Text("全部", bundle: .module), isSelected: !showsRecent) { showsAll = true }
            }
            if !showsRecent {
                SearchField(text: $query, prompt: Text("搜索表情", bundle: .module))
            }
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.cell, maximum: Self.cell), spacing: 0)], spacing: 0
                ) {
                    ForEach(showsRecent ? model.recent : EmojiCatalog.matching(query), id: \.self) { emoji in
                        Button {
                            pick(emoji)
                        } label: {
                            Text(verbatim: emoji.text)
                                .font(.system(size: Self.emojiSize))
                                .frame(width: Self.cell, height: Self.cell)
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(Space.s)
        .frame(width: Self.size.width, height: Self.size.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.emojiGrid")
    }
}

/// Finding emoji by name for the grid's search.
enum EmojiCatalog {
    /// The emoji whose Unicode name has `query` in it, all of them for no query.
    static func matching(_ query: String) -> [Emoji] {
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !words.isEmpty else { return Emoji.all }
        return named.filter { $0.name.contains(words) }.map(\.emoji)
    }

    /// Each emoji with its Unicode name, worked out once: the transform writes `\N{GRINNING FACE}`,
    /// and only the words inside count.
    private static let named: [(emoji: Emoji, name: String)] = Emoji.all.map { emoji in
        let name = (emoji.text.applyingTransform(.toUnicodeName, reverse: false) ?? "")
            .replacingOccurrences(of: "\\N{", with: " ").replacingOccurrences(of: "}", with: " ").lowercased()
        return (emoji, name)
    }
}
#endif
