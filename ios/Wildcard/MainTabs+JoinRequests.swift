import Contracts
import SwiftUI

extension MainTabs {
    /// Each request to join the captain's squad that this phone hasn't shown, in a banner on 今天
    /// (「小橘 申请加入小队 · 查看」) that stays until it is tapped or swiped away; 查看 opens 小队设置,
    /// where the captain answers. The dots by the squad's name and on 小队's gear stay while anyone
    /// waits. Kept with the broadcasts shown, by the request's id.
    func tellJoinRequests() {
        guard let member = today.home?.member.description, let requests = squad.joining?.requests else { return }
        for request in requests {
            let shown = "joinRequest-\(request.id)"
            guard !ShownBroadcasts.contains(shown, for: member) else { continue }
            today.tellJoinRequest(request.id, from: request.character?.nickname.text ?? "", open: open) {
                ShownBroadcasts.mark(shown, for: member)
            }
        }
    }
}
