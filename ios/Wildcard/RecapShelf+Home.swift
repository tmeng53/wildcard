import CheckInDomain
import Contracts
import RecapUI
import SwiftUI

extension RecapShelf.Squad {
    /// The squad 今天 shows, for its 战报: which squad, the reader and their day. Who was in it
    /// and how they looked come with each week's story.
    init(_ home: Home) {
        self.init(id: home.squad.id, today: LocalDay(at: .now, in: home.timeZone), viewer: home.member)
    }
}

/// The squad's newest 战报, once there is one, opening it.
struct RecapTile: View {
    let recap: RecapShelf

    var body: some View {
        if let story = recap.latest {
            RecapEntryTile(
                story: story, viewer: recap.cast?.reader, seen: recap.latestIsSeen, action: recap.openLatest)
        }
    }
}
