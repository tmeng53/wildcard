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
/// the same on the home's banner and in 通知: 「DEUCE CLUB 开门了 · 网球练满 3 天」,
/// 「解锁了网球拍 · 第一次打网球」. A piece is told by its store's wordmark, never its own name, so
/// it stays a surprise until the store shows it: 「LAP NINE 到新货了 · 跑步练满 5 天」.
public enum UnlockNames {
    public static func title(_ kind: Unlock.Kind, item: String) -> Text {
        switch kind {
        case .store: Text(copy: "\(StoreCopy.name(item)) 开门了", bundle: .module)
        case .prop: Text(copy: "解锁了\(EditorNames.variant(item, in: Slot("prop")))", bundle: .module)
        case .piece:
            if let store = storeOf(piece: item) {
                Text(copy: "\(StoreCopy.name(store)) 到新货了", bundle: .module)
            } else {
                // A piece this build has no art for yet.
                Text(copy: "商店街到新货了", bundle: .module)
            }
        }
    }

    /// A piece's own name, as 我的衣橱 says it, such as a coach's gift once it is opened.
    public static func piece(_ piece: String) -> Text {
        EditorNames.variant(piece, in: PlaceholderCharacter.slot(holding: piece) ?? Slot("prop"))
    }

    /// The store a piece hangs in, by the bundled art; nil for a piece this build doesn't have.
    public static func storeOf(piece: String) -> String? {
        (try? PlaceholderCharacter.editorChoices())?.wear.values.joined().first { $0.id == piece }?.store
    }

    /// How it opened, from the rule the server sent, so a changed rule needs no new copy. The
    /// rule's first sport stands for the rest (DEUCE CLUB takes 网球, 匹克球 and 壁球, and says 网球).
    public static func detail(_ unlock: Unlock) -> Text {
        guard let sport = unlock.sports.first else {
            return Text(copy: "随便练满 \(unlock.checkIns) 天", bundle: .module)
        }
        let name = sport.localizedName
        switch unlock.kind {
        case .store, .piece:
            return Text(copy: "\(name)练满 \(unlock.checkIns) 天", bundle: .module)
        case .prop:
            // Ball and racket sports are played (打), the rest trained (练).
            let played = ["racket", "ball"].contains(sport.entry?.category ?? "")
            return played ? Text(copy: "第一次打\(name)", bundle: .module) : Text(copy: "第一次练\(name)", bundle: .module)
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
            case .piece:
                if let store = UnlockNames.storeOf(piece: item) {
                    StoreBadge(store: store)
                } else {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(role: .fgDefault, in: .gym))
                }
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

/// A piece or prop on its own, filling its frame, as 商店街's tiles draw it; a store's badge. What a
/// broadcast gives shows this way on its celebration card. Nothing for art this build doesn't have.
public struct WardrobePicture: View {
    private let kind: Unlock.Kind
    private let item: String
    /// Every picture outside the editor shares one cache.
    @MainActor private static let thumbnails = ThumbnailCache()

    public init(_ kind: Unlock.Kind, item: String) {
        (self.kind, self.item) = (kind, item)
    }

    public var body: some View {
        Group {
            if kind == .store {
                StoreBadge(store: item)
            } else if let slot = PlaceholderCharacter.slot(holding: item) {
                Thumbnail(
                    outfit: wearing(item, in: slot), only: slot, crop: ThumbnailCrop.of(slot), cache: Self.thumbnails)
            }
        }
        .accessibilityHidden(true)
    }

    /// The one look every such picture is drawn on, wearing `item`: only `item` shows.
    private func wearing(_ item: String, in slot: Slot) -> Outfit {
        var outfit = PlaceholderCharacter.lifter
        outfit.variants[slot] = item
        return outfit
    }
}
#endif
