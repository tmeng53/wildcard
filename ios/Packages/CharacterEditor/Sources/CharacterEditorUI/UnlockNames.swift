#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// What a store opening or a prop unlocking says outside the editor, in the editor's own names,
/// the same on the home's banner and in 通知: 「DEUCE CLUB 开门了 · 网球练满 3 次」,
/// 「解锁了网球拍 · 第一次打网球」.
public enum UnlockNames {
    public static func title(_ kind: Unlock.Kind, item: String) -> Text {
        switch kind {
        case .store: Text("\(StoreCopy.name(item)) 开门了", bundle: .module)
        case .prop: Text("解锁了\(EditorNames.variant(item, in: Slot("prop")))", bundle: .module)
        }
    }

    /// How it opened, from the rule the server sent, so a changed rule needs no new copy. The
    /// rule's first sport stands for the rest (DEUCE CLUB takes 网球, 匹克球 and 壁球, and says 网球).
    public static func detail(_ unlock: Unlock) -> Text {
        guard let sport = unlock.sports.first else {
            return Text("随便练满 \(unlock.checkIns) 次", bundle: .module)
        }
        let name = sport.localizedName
        switch unlock.kind {
        case .store:
            return Text("\(name)练满 \(unlock.checkIns) 次", bundle: .module)
        case .prop:
            // Ball and racket sports are played (打), the rest trained (练).
            let played = ["racket", "ball"].contains(sport.entry?.category ?? "")
            return played ? Text("第一次打\(name)", bundle: .module) : Text("第一次练\(name)", bundle: .module)
        }
    }
}

/// A store's badge, or a prop's picture, on a white circle: the icon of its news in 通知.
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
