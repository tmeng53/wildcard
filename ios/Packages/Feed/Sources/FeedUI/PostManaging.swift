#if os(iOS)
import CheckInDomain
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// What the member's 「…」 on their own post opens, around the feed or a post's own page: the
/// compose page to edit it, full screen, and the question before deleting it. Only the surface
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
                    ComposeView(model: compose)
                        .environment(\.sceneTheme, theme)
                        .accentTone(.brand)
                }
            }
            // An alert, not a confirmation dialog: iOS 26 drops a dialog's 取消.
            .alert(
                Text("删掉这条动态？", bundle: .module), isPresented: confirming, presenting: model.confirmingDelete
            ) { post in
                Button(role: .destructive) {
                    Task {
                        if await model.delete(post) { deleted(post) }
                    }
                } label: {
                    Text("删除", bundle: .module)
                }
                .accessibilityIdentifier("post.delete.confirm")
                Button(role: .cancel) {
                } label: {
                    Text("取消", bundle: .module)
                }
            } message: { _ in
                Text("队友的回应和评论也会一起删掉", bundle: .module)
            }
            .alert(Text("没删掉，再试一次", bundle: .module), isPresented: deleteFailed) {
                Button(role: .cancel) {
                } label: {
                    Text("好", bundle: .module)
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

    private var confirming: Binding<Bool> {
        Binding {
            isActive && model.confirmingDelete != nil
        } set: {
            if !$0 { model.confirmingDelete = nil }
        }
    }

    private var deleteFailed: Binding<Bool> {
        Binding {
            isActive && model.deleteFailed
        } set: {
            if !$0 { model.deleteFailed = false }
        }
    }
}

// The member's own posts.
extension FeedModel {
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
            },
            close: { [weak self] in self?.editing = nil })
    }

    /// Deletes one of the member's posts, once they confirmed. False when it didn't go through.
    func delete(_ post: CheckInID) async -> Bool {
        guard let editor else { return false }
        do throws(CheckInError) {
            try await editor.delete(post)
        } catch {
            deleteFailed = true
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
