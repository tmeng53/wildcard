import CharacterEditorUI
import Contracts
import MeDomain
import NotificationsUI
import SwiftUI

/// What 通知 shows of the member's own: their character when it is empty, and an unlock's words.
extension MainTabs {
    /// The member's own character, on the empty 通知.
    var noticeViewer: NoticeViewer? {
        profile.overview.map { NoticeViewer(outfit: $0.character.outfit, persona: $0.character.persona) }
    }

    /// A store's, prop's or piece's words and badge on its 通知 row, as the home's banner says them.
    /// How a store or piece opened comes from the member's unlock; a prop's title says it all (the bell design).
    func unlockWords(_ kind: Unlock.Kind, item: String) -> UnlockWords {
        let unlock = profile.overview?.unlocks.first { $0.kind == kind && $0.id == item }
        return UnlockWords(
            title: UnlockNames.title(kind, item: item),
            detail: kind == .prop ? nil : unlock.map(UnlockNames.detail),
            icon: AnyView(WardrobeBadge(kind, item: item)))
    }
}
