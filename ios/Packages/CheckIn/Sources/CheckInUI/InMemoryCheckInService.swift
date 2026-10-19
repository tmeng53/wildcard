import CheckInDomain
import Contracts
import DesignSystem
import Foundation

/// A squad kept in memory, for previews, UI tests and builds before the API client lands. It
/// starts from a given board and applies each post with the same rules the API uses.
public actor InMemoryCheckInService: CheckInService {
    private var current: TodayBoard

    public init(board: TodayBoard) {
        current = board
    }

    /// The squad the screens are reviewed against: 本周小队 14/22 and 3 trained today (spec
    /// rev 186), on 跑道, in the ISO week of `now`.
    public static func sampleSquad(now: Date) -> InMemoryCheckInService {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return InMemoryCheckInService(
            board: TodayBoard(
                squadName: Bundle.module.localizedString(forKey: "周三不练腿俱乐部", value: nil, table: nil),
                scene: .track,
                weekNumber: calendar.component(.weekOfYear, from: now),
                progress: SquadWeekProgress(done: 14, goal: 22),
                trainedToday: 3,
                myStatus: .notCheckedIn,
                lastActivity: .sport(.run)))
    }

    public func board() async throws(CheckInError) -> TodayBoard {
        current
    }

    public func post(_ draft: CheckInDraft) async throws(CheckInError) -> TodayBoard {
        switch draft {
        case .trained(let activity, _):
            if current.myStatus != .trained {
                current.progress = current.progress.addingTrainedDay()
                current.trainedToday += 1
            }
            current.myStatus = .trained
            current.lastActivity = activity
        case .disclaimer:
            switch current.myStatus {
            case .trained: throw .alreadyTrained
            case .disclaimer: throw .disclaimerAlreadyPosted
            case .notCheckedIn: current.myStatus = .disclaimer
            }
        case .healthyMeal, .cheatMeal:
            break
        }
        return current
    }
}
