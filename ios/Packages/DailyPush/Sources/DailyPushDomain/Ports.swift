import Contracts

/// The server, as reacting from the push needs it. The extension passes the API adapter
/// (`Backend`); tests pass their own.
public protocol ReactionSender: Sendable {
    /// Sets the member's one emoji on a teammate's check-in, or takes it back when nil. Safe to
    /// repeat.
    func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(DailyPushError)
}

/// The server, as answering a request to join from the captain's push needs it. The extension
/// passes the API adapter (`Backend`); tests pass their own.
public protocol JoinRequestAnswerer: Sendable {
    /// Lets the member in (`approve`) or turns them away. Answering again the same way is a
    /// success; `.squadFull` when 同意 finds no room, `.answeredElsewhere` when the request no
    /// longer waits, `.notSent` for anything else.
    func answer(_ request: JoinRequestID, in squad: SquadID, approve: Bool) async throws(DailyPushError)
}

/// Where the push sends the member when they open the app from it: 动态 from the header and
/// 「还有 n 条」, 打卡 from 我去发一个. A push view can't open a link of its own, so it leaves this
/// for the app, then opens it the way a tap on the push does.
public enum PushDestination: String, Sendable {
    case feed
    case checkIn
}
