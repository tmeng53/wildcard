import AppIntents
import Contracts
import Foundation
import WidgetKit

/// 接受 on the coach's face: accepts today's challenge without opening the app. WidgetKit reads
/// the widgets again once it returns, which shows 完成 in its place.
struct AcceptChallengeIntent: AppIntent {
    static let title: LocalizedStringResource = "接受今日挑战"
    static let isDiscoverable = false

    @Parameter(title: "小队") var squad: String
    @Parameter(title: "便条") var note: String

    init() {}

    init(squad: SquadID, note: String) {
        self.squad = squad.description
        self.note = note
    }

    func perform() async throws -> some IntentResult {
        guard case .signedIn(let session) = await WidgetSession.open(), let id = UUID(uuidString: squad),
            let note = Int(note)
        else { return .result() }
        _ = try? await session.api.answerChallenge(of: note, in: SquadID(id), with: .accepted, reason: nil)
        return .result()
    }
}

/// 完成 on the coach's face: marks today's challenge done, as 我完成了 does in the app.
struct CompleteChallengeIntent: AppIntent {
    static let title: LocalizedStringResource = "完成今日挑战"
    static let isDiscoverable = false

    @Parameter(title: "小队") var squad: String
    @Parameter(title: "便条") var note: String

    init() {}

    init(squad: SquadID, note: String) {
        self.squad = squad.description
        self.note = note
    }

    func perform() async throws -> some IntentResult {
        guard case .signedIn(let session) = await WidgetSession.open(), let id = UUID(uuidString: squad),
            let note = Int(note)
        else { return .result() }
        _ = try? await session.api.completeChallenge(of: note, in: SquadID(id))
        return .result()
    }
}
