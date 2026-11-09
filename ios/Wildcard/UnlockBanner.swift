import CharacterEditorUI
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// The notice that a 练了 unlocked a store, a prop or a piece (approved 2026-11-02, design A; glass
/// on every page 2026-11-08): 「DEUCE CLUB 开门了 · 网球练满 3 次」, 「解锁了网球拍 · 第一次打网球」,
/// 「LAP NINE 到新货了」, with the store's sign, or a prop's sport, and 去看看, which opens the editor
/// there. Its words are `CharacterEditorUI`'s `UnlockNames`, the same as on 通知's row.
struct UnlockBanner: View {
    let unlock: Unlock

    var body: some View {
        NoticeBanner(
            UnlockNames.title(unlock.kind, item: unlock.id), detail: UnlockNames.detail(unlock),
            action: Text("去看看")
        ) {
            switch unlock.kind {
            // A store opening and new pieces in one both show the store's sign.
            case .store, .piece: WardrobeBadge(unlock.kind, item: unlock.id)
            case .prop: NoticeSymbol(systemImage: unlock.sports.first?.symbol ?? "gift.fill")
            }
        }
    }
}
