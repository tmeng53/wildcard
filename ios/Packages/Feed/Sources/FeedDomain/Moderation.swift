import Contracts

/// What a member reports (举报): a teammate's post, a teammate's comment under one, or the coach's
/// line there. The coach's lines name the squad whose coach said them.
public enum ReportTarget: Hashable, Sendable {
    case post(CheckInID)
    case comment(CommentID, post: CheckInID)
    /// The coach's line under a post, by the coach.
    case coachReply(CoachID, post: CheckInID, squad: SquadID)
    /// The coach's answer to a member's comment, by that comment.
    case coachAnswer(answering: CommentID, post: CheckInID, squad: SquadID)

    /// The post it is, or is under.
    public var checkIn: CheckInID {
        switch self {
        case .post(let id), .comment(_, post: let id), .coachReply(_, post: let id, _),
            .coachAnswer(_, post: let id, _):
            id
        }
    }
}

extension FeedStore {
    /// The member reports a post, a comment or the coach's line: once the server took it, it is
    /// gone from here (the coach's line from `FeedCoach`, with `hide(_:)`). False when it didn't
    /// go through; `failure` says why.
    @discardableResult
    public func report(_ target: ReportTarget) async -> Bool {
        do {
            try await source.report(target)
        } catch {
            failure = error
            return false
        }
        hide(target)
        return true
    }

    /// The member blocks a teammate: once the server took it, their posts, comments and reactions
    /// are gone from here. False when it didn't go through; `failure` says why.
    @discardableResult
    public func block(_ member: MemberID) async -> Bool {
        do {
            try await source.block(member)
        } catch {
            failure = error
            return false
        }
        hide(member)
        return true
    }

    /// Takes what was reported out of what is loaded.
    func hide(_ target: ReportTarget) {
        switch target {
        case .post(let id):
            loaded[id] = nil
        case .comment(let comment, post: let id):
            loaded[id]?.comments.removeAll { $0.id == comment }
        case .coachReply, .coachAnswer:
            break
        }
    }

    /// Takes a blocked member's posts, comments and reactions out of what is loaded.
    func hide(_ member: MemberID) {
        loaded = loaded.filter { $0.value.author != member }
        for id in Array(loaded.keys) {
            guard var post = loaded[id] else { continue }
            post.comments.removeAll { $0.member == member }
            if post.reactions.kind(of: member) != nil {
                post.reactions = post.reactions.setting(nil, for: member, at: post.checkIn.createdAt)
            }
            loaded[id] = post
        }
    }
}

extension FeedCoach {
    /// Takes the coach's reported line out of what was read.
    public func hide(_ target: ReportTarget) {
        switch target {
        case .coachReply(_, post: let post, _): forgetReply(on: post)
        case .coachAnswer(answering: let comment, post: let post, _): forgetAnswer(to: comment, on: post)
        case .post, .comment: break
        }
    }
}
