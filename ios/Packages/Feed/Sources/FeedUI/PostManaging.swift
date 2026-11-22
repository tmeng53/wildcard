#if os(iOS)
import CheckInDomain
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// What the member's 「…」 on their own post opens, around the feed or a post's own page: the
/// compose page to edit it, full screen, 存成绩卡's page, and deleting it once the menu's question was answered. Only the surface
/// on top (`isActive`) presents them, as with the emoji bar.
struct PostManaging: ViewModifier {
    @Environment(\.sceneTheme) private var theme
    @Bindable var model: FeedModel
    let isActive: Bool
    /// Called once the post is deleted, so its own page can close.
    let deleted: (CheckInID) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: editing) {
                if let compose = model.editing {
                    // A stack of its own, so the place pill's name pushes the place's page over it.
                    NavigationStack {
                        ComposeView(model: compose)
                            .navigationRoot()
                    }
                    .environment(\.sceneTheme, theme)
                    .accentTone(.brand)
                }
            }
            .sheet(item: scoreCard) { card in
                ScoreCardSheet(model: card, store: model.store) { model.scoreCard = nil }
                    .environment(\.sceneTheme, theme)
            }
            .onChange(of: model.deleting) { _, post in
                guard isActive, let post else { return }
                model.deleting = nil
                Task {
                    if await model.delete(post) { deleted(post) }
                }
            }
            .alert(failedTitle, isPresented: failedShown) {
                Button(role: .cancel) {
                } label: {
                    Text(copy: "好", bundle: .module)
                }
            }
    }

    private var editing: Binding<Bool> {
        Binding {
            isActive && model.editing != nil
        } set: {
            if !$0 { model.editing = nil }
        }
    }

    private var scoreCard: Binding<ScoreCardModel?> {
        Binding {
            isActive ? model.scoreCard : nil
        } set: {
            if $0 == nil { model.scoreCard = nil }
        }
    }

    private var failedShown: Binding<Bool> {
        Binding {
            isActive && model.failed != nil
        } set: {
            if !$0 { model.failed = nil }
        }
    }

    private var failedTitle: Text {
        switch model.failed {
        case .report: Text(copy: "没举报成功，再试一次", bundle: .module)
        case .block: Text(copy: "没拉黑成功，再试一次", bundle: .module)
        case .delete, nil: Text(copy: "没删掉，再试一次", bundle: .module)
        }
    }
}

// The member's own posts.
extension FeedModel {
    /// A page of the member's own is over the feed (the compose page or the 成绩卡), so the
    /// cards' characters hold still under it instead of drawing every frame unseen (#924).
    var isCovered: Bool { editing != nil || scoreCard != nil }

    /// Whether the member can edit and delete `post`: it is theirs.
    func canManage(_ post: FeedPost) -> Bool { editor != nil && post.author == viewer }

    /// Opens the compose page on one of the member's posts, as it is.
    func edit(_ post: FeedPost) {
        guard let editor, post.author == viewer else { return }
        closeBar()
        let store = store
        editing = ComposeModel(
            editing: post.checkIn, editor: editor, loadPhoto: { await store.photo($0) },
            saved: { [weak self] checkIn in
                self?.apply(.edited(checkIn))
                self?.editing = nil
                // Back on 动态, the edited post is held at the top, so the change is what the
                // member sees even when the list moved under the compose page (#924).
                self?.focus = checkIn.id
            },
            close: { [weak self] in self?.editing = nil })
    }

    /// Deletes one of the member's posts, once they confirmed. False when it didn't go through.
    func delete(_ post: CheckInID) async -> Bool {
        guard let editor else { return false }
        do throws(CheckInError) {
            try await editor.delete(post)
        } catch {
            failed = .delete
            return false
        }
        apply(.deleted(post))
        return true
    }

    fileprivate func apply(_ change: PostChange) {
        store.apply(change)
        changed?(change)
    }
}

extension View {
    func managesPosts(_ model: FeedModel, isActive: Bool = true, deleted: @escaping (CheckInID) -> Void = { _ in })
        -> some View
    {
        modifier(PostManaging(model: model, isActive: isActive, deleted: deleted))
    }
}
#endif
