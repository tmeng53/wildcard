#if os(iOS)
import SwiftUI

/// The editor's own names for what training unlocks, for the home's notice that one opened: a
/// store's wordmark (DEUCE CLUB) and a prop's name (网球拍).
public enum UnlockNames {
    public static func store(_ id: String) -> Text { StoreCopy.name(id) }
    public static func prop(_ id: String) -> Text { EditorNames.variant(id, in: "prop") }
}
#endif
