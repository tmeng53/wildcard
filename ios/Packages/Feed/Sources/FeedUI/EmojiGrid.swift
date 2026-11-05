#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// Where 动态's emoji picker opens over a post's button.
enum EmojiGrid {
    static let size = CGSize(width: 320, height: 340)
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
