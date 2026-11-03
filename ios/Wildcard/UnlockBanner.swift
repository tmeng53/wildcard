import CharacterEditorUI
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// The home's notice that a 练了 unlocked a store, a prop or a piece (approved 2026-11-02, design
/// A): 「DEUCE CLUB 开门了 · 网球练满 3 次」, 「解锁了网球拍 · 第一次打网球」, 「LAP NINE 到新货了 ·
/// 跑步练满 5 次」, which never names the piece. A tap opens the editor there. The words for what opened come from the editor; how it opened from the rule
/// the server sent, so a changed rule needs no new copy.
struct UnlockBanner: View {
    let unlock: Unlock
    private let glyph: Double = 17

    var body: some View {
        NoticeBanner(title, detail: detail, showsChevron: true) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Color(role: .fgOnAccent, in: .gym))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgAccent, in: .gym))
                .accessibilityHidden(true)
        }
    }

    private var title: Text {
        switch unlock.kind {
        case .store: Text("\(UnlockNames.store(unlock.id)) 开门了")
        case .prop: Text("解锁了\(UnlockNames.prop(unlock.id))")
        case .piece: Text("\(UnlockNames.storeOfPiece(unlock.id)) 到新货了")
        }
    }

    /// How it opened: the rule's first sport stands for the rest (DEUCE CLUB takes 网球, 匹克球
    /// and 壁球, and says 网球).
    private var detail: Text {
        guard let sport = unlock.sports.first else { return Text("随便练满 \(unlock.checkIns) 次") }
        switch unlock.kind {
        case .store, .piece: return Text("\(sport.localizedName)练满 \(unlock.checkIns) 次")
        case .prop:
            // Ball and racket sports are played (打), the rest trained (练).
            let played = ["racket", "ball"].contains(sport.entry?.category ?? "")
            return played ? Text("第一次打\(sport.localizedName)") : Text("第一次练\(sport.localizedName)")
        }
    }

    private var symbol: String {
        switch unlock.kind {
        case .store: "storefront.fill"
        case .piece: "shippingbox.fill"
        case .prop: unlock.sports.first?.symbol ?? "gift.fill"
        }
    }
}
