import APIContract
import Contracts
import FeedDomain
import Foundation

/// 历史动态 over our API: the member's own posts a page at a time, each with the reactions they
/// see, and each photo from the URL the page signed for it.
public struct APIMyPostsSource: MyPostsSource {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func myPosts(kind: PostKind?, after: String?) async throws(FeedError) -> MyPostsPage {
        do throws(APIError) {
            let page = try await api.myPostsWire(kind: kind.map(\.wire), after: after)
            let posts = try api.read { () throws(ContractsError) in
                try page.posts.map { post throws(ContractsError) in
                    try FeedPost(checkIn: post.checkIn, reactions: post.reactions, comments: post.comments)
                }
            }
            return MyPostsPage(
                posts: posts, next: page.next,
                counts: page.counts.map { MyPostCounts(posts: $0.posts, reactions: $0.reactions) })
        } catch {
            throw FeedError(error)
        }
    }

    public func photo(_ ref: PhotoRef) async -> Data? {
        guard let url = ref.viewURL else { return nil }
        return await api.photo(at: url)
    }
}

extension PostKind {
    fileprivate var wire: Operations.ListMyPosts.Input.Query.KindPayload {
        switch self {
        case .trained: .trained
        case .healthyMeal: .healthyMeal
        case .cheatMeal: .cheatMeal
        case .disclaimer: .disclaimer
        }
    }
}
