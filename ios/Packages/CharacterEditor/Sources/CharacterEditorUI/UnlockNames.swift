#if os(iOS)
import AvatarArt
import SwiftUI

/// The editor's own names for what training unlocks, for the home's notice that one opened: a
/// store's wordmark (DEUCE CLUB) and a prop's name (网球拍). A piece is told by its store's
/// wordmark, never its own name: the box keeps it a surprise until the store opens it.
public enum UnlockNames {
    public static func store(_ id: String) -> Text { StoreCopy.name(id) }
    public static func prop(_ id: String) -> Text { EditorNames.variant(id, in: "prop") }
    public static func storeOfPiece(_ id: String) -> Text {
        let store = (try? PlaceholderCharacter.editorChoices())?.wear.values.joined().first { $0.id == id }?.store
        return store.map(StoreCopy.name) ?? Text(verbatim: "")
    }
}
#endif
