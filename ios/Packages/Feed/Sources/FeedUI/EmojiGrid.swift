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

/// Every single emoji the grid offers, faces first, each skin tone left to the keyboard.
enum EmojiCatalog {
    static let all: [Emoji] = {
        let ranges: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF, 0x1F300...0x1F5FF, 0x1F680...0x1F6FF,
            0x2600...0x27BF,
        ]
        var emoji: [Emoji] = []
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                    !(0x1F3FB...0x1F3FF).contains(value), let one = try? Emoji(String(scalar))
                else { continue }
                emoji.append(one)
            }
        }
        // ❤️ draws as an emoji only with its variation selector.
        if let heart = try? Emoji("❤️") { emoji.insert(heart, at: 0) }
        return emoji
    }()

    /// The emoji whose Unicode name has `query` in it, all of them for no query.
    static func matching(_ query: String) -> [Emoji] {
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !words.isEmpty else { return all }
        return all.filter { name(of: $0).contains(words) }
    }

    private static func name(of emoji: Emoji) -> String {
        (emoji.text.applyingTransform(.toUnicodeName, reverse: false) ?? "").lowercased()
    }
}
#endif
