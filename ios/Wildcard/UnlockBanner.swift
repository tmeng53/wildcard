import CharacterEditorUI
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// The home's notice that a 练了 unlocked a store, a prop or a piece (approved 2026-11-02, design
/// A): 「DEUCE CLUB 开门了 · 网球练满 3 次」, 「解锁了网球拍 · 第一次打网球」, 「LAP NINE 到新货了」.
/// A tap opens the editor there. Its words are `CharacterEditorUI`'s `UnlockNames`, the same as on 通知's row.
struct UnlockBanner: View {
    let unlock: Unlock
    private let glyph: Double = 17

    var body: some View {
        NoticeBanner(
            UnlockNames.title(unlock.kind, item: unlock.id), detail: UnlockNames.detail(unlock), showsChevron: true
        ) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Color(role: .fgOnAccent, in: .gym))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgAccent, in: .gym))
                .accessibilityHidden(true)
        }
    }

    private var symbol: String {
        switch unlock.kind {
        // A store opening and new pieces in one both show the 商店街 storefront.
        case .store, .piece: "storefront.fill"
        case .prop: unlock.sports.first?.symbol ?? "gift.fill"
        }
    }
}
