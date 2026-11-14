import Contracts
import Foundation
import Testing

@testable import DailyPushDomain

private let requestID = "5c3e7a91-4b2d-4e8f-a6c1-2d9b8e7f6a05"
private let squadID = "6f1c2a5e-8d3b-4f7a-9c2e-1b4d5a6e7f80"
private let memberID = "00000000-0000-4000-8000-00000000000a"

/// The captain's push as the server writes it (`push-samples.json`'s `push.joinRequest`).
private func event(note: String? = "我是小橘，阿杰拉我来的", look: Bool = true, kind: String = "joinRequest") -> Data {
    let noteField = note.map { #", "note": "\#($0)""# } ?? ""
    let lookField = look ? #", "look": {"persona": "shy", "variants": {"body": "lop"}, "colors": {}}"# : ""
    return Data(
        """
        {"kind": "\(kind)", "squadId": "\(squadID)", "request": "\(requestID)", "member": "\(memberID)",
         "nickname": "小橘"\(noteField)\(lookField)}
        """.utf8)
}

@Test func readsWhoAskedTheirNoteAndLook() throws {
    let push = try JoinRequestPush(event: event())
    #expect(push.request.description == requestID)
    #expect(push.squad.description == squadID)
    #expect(push.member.description == memberID)
    #expect(push.nickname == "小橘")
    #expect(push.note == "我是小橘，阿杰拉我来的")
    #expect(push.look == CharacterLook(persona: "shy", variants: ["body": "lop"]))
}

@Test func aBlankNoteAndNoLookReadAsNone() throws {
    let push = try JoinRequestPush(event: event(note: "  ", look: false))
    #expect(push.note == nil)
    #expect(push.look == nil)
}

@Test func anotherKindOfPushIsUnreadable() {
    #expect(throws: DailyPushError.unreadable) { try JoinRequestPush(event: event(kind: "dailyProgress")) }
    #expect(throws: DailyPushError.unreadable) { try JoinRequestPush(event: Data("{}".utf8)) }
}

/// Answers as told, recording each call.
private actor Answerer: JoinRequestAnswerer {
    var failure: DailyPushError?
    private(set) var calls: [Bool] = []

    init(failing failure: DailyPushError? = nil) { self.failure = failure }

    func succeed() { failure = nil }

    func answer(_ request: JoinRequestID, in squad: SquadID, approve: Bool) async throws(DailyPushError) {
        calls.append(approve)
        if let failure { throw failure }
    }
}

@MainActor @Test func approvingLetsThemInOnce() async throws {
    let answerer = Answerer()
    let answer = JoinRequestAnswer(push: try JoinRequestPush(event: event()), answerer: answerer)
    await answer.answer(approve: true)
    #expect(answer.state == .approved)
    await answer.answer(approve: true)
    await answer.answer(approve: false)
    #expect(answer.state == .approved)
    #expect(await answerer.calls == [true])
}

@MainActor @Test func decliningTurnsThemAway() async throws {
    let answer = JoinRequestAnswer(push: try JoinRequestPush(event: event()), answerer: Answerer())
    await answer.answer(approve: false)
    #expect(answer.state == .declined)
    #expect(!answer.canApprove)
    #expect(!answer.canDecline)
}

@MainActor @Test func aFullSquadLeavesOnlyDecline() async throws {
    let answerer = Answerer(failing: .squadFull)
    let answer = JoinRequestAnswer(push: try JoinRequestPush(event: event()), answerer: answerer)
    await answer.answer(approve: true)
    #expect(answer.state == .full)
    #expect(!answer.canApprove)
    #expect(answer.canDecline)
    await answerer.succeed()
    await answer.answer(approve: false)
    #expect(answer.state == .declined)
    #expect(await answerer.calls == [true, false])
}

@MainActor @Test func aRequestAnsweredElsewhereCloses() async throws {
    let answer = JoinRequestAnswer(
        push: try JoinRequestPush(event: event()), answerer: Answerer(failing: .answeredElsewhere))
    await answer.answer(approve: false)
    #expect(answer.state == .closed)
    #expect(!answer.canApprove)
    #expect(!answer.canDecline)
}

@MainActor @Test func aFailedAnswerCanBeTappedAgain() async throws {
    let answerer = Answerer(failing: .notSent)
    let answer = JoinRequestAnswer(push: try JoinRequestPush(event: event()), answerer: answerer)
    await answer.answer(approve: true)
    #expect(answer.state == .failed)
    await answerer.succeed()
    await answer.answer(approve: true)
    #expect(answer.state == .approved)
    #expect(await answerer.calls == [true, true])
}
