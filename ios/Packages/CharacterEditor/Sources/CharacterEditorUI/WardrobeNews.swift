#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// What a store opening or a prop unlocking says outside the editor (通知, a notice banner), in
/// the editor's own names: DEUCE CLUB 开门了, with how it opened under it.
public enum WardrobeNews {
    public static func title(_ kind: Unlock.Kind, item: String) -> Text {
        switch kind {
        case .store: Text("\(StoreCopy.name(item)) 开门了", bundle: .module)
        case .prop: Text("解锁了\(EditorNames.variant(item, in: Slot("prop")))", bundle: .module)
        }
    }

    /// What opened a store, as the approved bell design words it (网球练满 3 次); nil for a prop,
    /// whose title says it all, and for a store this build has no words for.
    public static func detail(_ kind: Unlock.Kind, item: String) -> Text? {
        guard kind == .store, let key = opened[item] else { return nil }
        return Text(LocalizedStringKey(key), bundle: .module)
    }

    private static let opened = [
        "lap": "跑步练满 3 次", "nolook": "篮球练满 3 次", "moss": "攀岩或徒步练满 3 次", "halfmoon": "随便练满 3 次",
        "deuce": "网球练满 3 次",
    ]
}

/// A store's badge, or a prop's picture, on a white circle: the icon of its news.
public struct WardrobeBadge: View {
    private let kind: Unlock.Kind
    private let item: String

    public init(_ kind: Unlock.Kind, item: String) {
        (self.kind, self.item) = (kind, item)
    }

    public var body: some View {
        ZStack {
            Color(role: .bgCanvas, in: .gym)
            switch kind {
            case .store:
                StoreBadge(store: item)
            case .prop:
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(role: .fgDefault, in: .gym))
            }
        }
        .overlay { Circle().strokeBorder(Color(role: .borderDefault, in: .gym), lineWidth: 0.8) }
        .accessibilityHidden(true)
    }
}
#endif
