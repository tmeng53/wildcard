#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI
import UIKit

/// What didn't go through, for the alert that says so.
enum FailedAction: Hashable {
    case delete
    case report
    case block
}

/// Which of the coach's lines under a post: its reply, by the coach, or its answer to a comment.
enum CoachLine: Hashable {
    case reply(CoachID)
    case answer(CommentID)
}

// 举报 and 拉黑 (App Review 1.2): on a teammate's post, a teammate's comment and the coach's line.
extension FeedModel {
    /// Whether the member can report `post` and block its author: it is a teammate's.
    func canModerate(_ post: FeedPost) -> Bool { post.author != viewer }

    /// 举报, once the member confirmed: it leaves this phone's 动态 once the server took it.
    func report(_ target: ReportTarget) {
        closeBar()
        Task {
            if await store.report(target) {
                coach?.hide(target)
            } else {
                failed = .report
            }
        }
    }

    /// 拉黑, once the member confirmed: their posts, comments and reactions leave once the
    /// server took it.
    func block(_ member: MemberID) {
        closeBar()
        Task {
            if !(await store.block(member)) { failed = .block }
        }
    }

    /// Holding a teammate's comment, after 复制: 举报 and 拉黑, each asking first.
    func moderationItems(for comment: Comment, on post: CheckInID) -> [GlassMenuItem] {
        guard comment.member != viewer else { return [] }
        return [
            Self.reportItem(
                Text(copy: "举报这条评论？", bundle: .module), id: "post.comment.report"
            ) { [weak self] in self?.report(.comment(comment.id, post: post)) },
            blockItem(comment.member, id: "post.comment.block"),
        ]
    }

    /// Holding the coach's line or answer: 复制, and 举报 where the coach's squad is known.
    func coachItems(_ line: CoachLine, text: String, on post: CheckInID) -> [GlassMenuItem] {
        var items = [
            GlassMenuItem(Text(copy: "复制", bundle: .module), systemImage: "doc.on.doc", id: "post.coach.copy") {
                UIPasteboard.general.string = text
            }
        ]
        if let target = coachLine(line, on: post) {
            let question = Text(copy: "举报教练的这句话？", bundle: .module)
            items.append(Self.reportItem(question, id: "post.coach.report") { [weak self] in self?.report(target) })
        }
        return items
    }

    /// 举报, asking `question` first in the menu.
    static func reportItem(_ question: Text, id: String, action: @escaping @MainActor () -> Void) -> GlassMenuItem {
        GlassMenuItem(
            Text(copy: "举报", bundle: .module), systemImage: "exclamationmark.bubble", id: id,
            confirm: .init(
                question, label: Text(copy: "举报", bundle: .module), id: "\(id).confirm"),
            action: action)
    }

    /// 拉黑 and the member's name, asking first in the menu.
    func blockItem(_ member: MemberID, id: String) -> GlassMenuItem {
        let name = displayName(of: member)
        return GlassMenuItem(
            Text(copy: "拉黑 \(name)", bundle: .module), systemImage: "hand.raised", role: .destructive, id: id,
            confirm: .init(
                Text(copy: "拉黑 \(name)？", bundle: .module),
                message: Text(
                    copy: "你们互相看不到对方的动态和评论，也不会收到对方的推送。\(name) 还在小队里，不会收到通知。",
                    bundle: .module),
                label: Text(copy: "拉黑", bundle: .module), id: "\(id).confirm")
        ) { [weak self] in
            self?.block(member)
        }
    }

    /// A coach's line under a post, to report: in the squad whose coach said it.
    private func coachLine(_ line: CoachLine, on post: CheckInID) -> ReportTarget? {
        guard let squad = coach?.squad else { return nil }
        return switch line {
        case .reply(let coach): .coachReply(coach, post: post, squad: squad)
        case .answer(let comment): .coachAnswer(answering: comment, post: post, squad: squad)
        }
    }
}

/// 「…」 on a teammate's post: 举报 and 拉黑, each asking first, in the menu.
struct ModerationMenu: View {
    let model: FeedModel
    let post: FeedPost

    var body: some View {
        HeaderMenu(
            Text(copy: "举报或拉黑", bundle: .module), on: .ink,
            items: [
                FeedModel.reportItem(Text(copy: "举报这条动态？", bundle: .module), id: "post.report") {
                    model.report(.post(post.id))
                },
                model.blockItem(post.author, id: "post.block"),
            ]
        )
        .accessibilityIdentifier("post.moderate.\(post.id)")
    }
}
#endif
