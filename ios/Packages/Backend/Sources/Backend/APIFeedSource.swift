import APIContract
import Contracts
import FeedDomain
import Foundation

/// 动态 over our API: the squad's list with each check-in's reactions and comments in one call,
/// one post's own page, the characters from the squad's today, and each photo from the URL the
/// list signed for it.
public struct APIFeedSource: FeedSource {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func posts(in squad: SquadID, from first: LocalDay, through last: LocalDay) async throws(FeedError)
        -> [FeedPost]
    {
        do throws(APIError) {
            let list = try await api.checkInsWire(of: squad, from: first, through: last)
            return try api.read { () throws(ContractsError) in
                try list.posts.map { post throws(ContractsError) in
                    try FeedPost(checkIn: post.checkIn, reactions: post.reactions, comments: post.comments)
                }
            }
        } catch {
            throw FeedError(error)
        }
    }

    public func post(_ id: CheckInID) async throws(FeedError) -> FeedPost {
        do throws(APIError) {
            let post = try await api.postWire(id)
            return try api.read { () throws(ContractsError) in
                try FeedPost(checkIn: post.checkIn, reactions: post.reactions, comments: post.comments)
            }
        } catch {
            throw FeedError(error)
        }
    }

    public func comment(_ text: CommentText, id: CommentID, replyingTo member: MemberID?, on checkIn: CheckInID)
        async throws(FeedError) -> Comment
    {
        do throws(APIError) {
            return try await api.comment(text, id: id, replyingTo: member, on: checkIn)
        } catch {
            throw FeedError(error)
        }
    }

    public func deleteComment(_ id: CommentID, on checkIn: CheckInID) async throws(FeedError) {
        do throws(APIError) {
            try await api.deleteComment(id, on: checkIn)
        } catch {
            throw FeedError(error)
        }
    }

    public func characters(in squad: SquadID) async throws(FeedError) -> [MemberID: MemberCharacter] {
        do throws(APIError) {
            let today = try await api.today(of: squad)
            var characters: [MemberID: MemberCharacter] = [:]
            for mate in today.members {
                characters[mate.member] = mate.character
            }
            return characters
        } catch {
            throw FeedError(error)
        }
    }

    public func photo(_ ref: PhotoRef) async -> Data? {
        guard let url = ref.viewURL else { return nil }
        return await api.photo(at: url)
    }

    public func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(FeedError) {
        do throws(APIError) {
            if let emoji {
                try await api.react(emoji, to: checkIn)
            } else {
                try await api.removeReaction(from: checkIn)
            }
        } catch {
            throw FeedError(error)
        }
    }
}

extension FeedPost {
    /// A post as the API sends it, in the feed or on its own page.
    init(
        checkIn: Components.Schemas.CheckIn, reactions: [Components.Schemas.ReactionEntry],
        comments: [Components.Schemas.CommentEntry]
    ) throws(ContractsError) {
        self.init(
            checkIn: try CheckIn(checkIn),
            reactions: Responses(
                try reactions.map { entry throws(ContractsError) in
                    let reaction = try Reaction(entry)
                    return Responses<Emoji>.Response(
                        member: reaction.member, kind: reaction.emoji, moment: reaction.reactedAt)
                }),
            comments: try comments.map(Comment.init))
    }
}

extension FeedError {
    /// What a failed API call means for the feed.
    init(_ error: APIError) {
        self =
            switch error {
            case .unavailable: .notSent
            case .account(.signedOut), .account(.credentialRejected), .account(.canceled): .signedOut
            case .account: .notSent
            case .refused(.squadNotJoined): .notInSquad
            case .refused(.checkInNotFound): .postGone
            case .refused, .unreadableResponse: .refused
            }
    }
}
