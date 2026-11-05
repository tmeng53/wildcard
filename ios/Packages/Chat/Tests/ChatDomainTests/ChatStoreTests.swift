import Contracts
import Foundation
import Testing

@testable import ChatDomain

private let squad = SquadID(UUID(uuidString: "00000000-0000-0000-0000-0000000000a1") ?? UUID())
private let viewer = MemberID(UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID())
private let mia = MemberID(UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID())
private let coach = CoachSpeaker(id: "xiaohun", name: "毛头")
private let start = Date(timeIntervalSince1970: 1_793_750_400)

private func id(_ number: Int) -> ChatMessageID {
    ChatMessageID(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID())
}

private func character(_ name: String) throws -> MemberCharacter {
    MemberCharacter(nickname: try Nickname(name), look: CharacterLook(persona: "sunny", variants: [:]))
}

private func message(_ number: Int, by author: ChatAuthor, _ text: String, replyTo: ChatMessageID? = nil) -> ChatMessage {
    ChatMessage(
        id: id(number), seq: number, author: author, kind: .text, text: text, replyTo: replyTo, mentions: [],
        mentionsCoach: false, sentAt: start.addingTimeInterval(Double(number) * 60), reactions: [])
}

/// Ids handed out in order, from 100.
private final class Ids: @unchecked Sendable {
    // Only the main actor's store calls it, one at a time.
    private var next = 100
    func make() -> ChatMessageID {
        defer { next += 1 }
        return id(next)
    }
}

@MainActor
private func store(_ source: InMemoryChatSource) -> ChatStore {
    let ids = Ids()
    return ChatStore(source: source, squad: squad, viewer: viewer, now: { start }, newID: { ids.make() })
}

private func source(
    _ messages: [ChatMessage] = [], coaches: ChatCoaches = ChatCoaches(current: coach, names: [:])
) throws -> InMemoryChatSource {
    InMemoryChatSource(
        viewer: viewer, squad: squad, messages: messages, characters: [viewer: try character("我"), mia: try character("Mia")],
        coaches: coaches, now: { start })
}

private func draft(_ text: String, replyTo: ChatMessageID? = nil, coach: Bool = false) throws -> ChatDraft {
    ChatDraft(text: try #require(MessageText(text)), replyTo: replyTo, mentions: [], mentionsCoach: coach)
}

@MainActor
struct ChatStoreTests {
    @Test func loadsOldestFirst() async throws {
        let chat = store(try source([message(2, by: .member(mia), "二"), message(1, by: .coach("xiaohun"), "一")]))
        await chat.load()
        #expect(chat.phase == .current)
        #expect(chat.lines.map(\.message.text) == ["一", "二"])
        #expect(chat.name(of: .coach("xiaohun")) == "毛头")
        #expect(chat.name(of: .member(mia)) == "Mia")
        #expect(!chat.isEmpty)
    }

    @Test func anEmptyChatIsEmptyOnceLoaded() async throws {
        let chat = store(try source())
        #expect(!chat.isEmpty)
        await chat.load()
        #expect(chat.isEmpty)
    }

    @Test func aFailedMessageStaysAndARetrySavesItOnce() async throws {
        let server = try source()
        let chat = store(server)
        await chat.load()
        await server.setOffline(true)
        await chat.send(try draft("在吗"))
        #expect(chat.lines.map(\.delivery) == [.failed])
        #expect(chat.failure == nil)
        await server.setOffline(false)
        await chat.retry(id(100))
        await chat.retry(id(100))
        #expect(chat.lines.map(\.delivery) == [.sent])
        #expect(chat.lines.map(\.message.text) == ["在吗"])
        #expect(await server.sendCalls == [id(100), id(100)])
        await chat.load()
        #expect(chat.lines.count == 1)
    }

    @Test func theCoachAnswersAnAtWithItsDotsFirst() async throws {
        let server = try source()
        let chat = store(server)
        await chat.load()
        await chat.listen()
        await chat.send(try draft("@毛头 今天练啥", coach: true))
        // The answer goes out on its own task; wait for it.
        for _ in 0..<100 where chat.lines.count < 2 { await Task.yield() }
        #expect(chat.lines.map(\.message.author) == [.member(viewer), .coach("xiaohun")])
        #expect(chat.lines.last?.message.replyTo == id(100))
        #expect(chat.coachTyping == nil)
    }

    @Test func typingShowsUntilTheCoachSpeaks() async throws {
        let chat = store(try source())
        await chat.load()
        await chat.heard(.coachTyping(squad, "xiaohun", typing: true))
        #expect(chat.coachTyping == "xiaohun")
        await chat.heard(.message(squad, message(5, by: .coach("xiaohun"), "来了"), quoted: nil))
        #expect(chat.coachTyping == nil)
        let other = SquadID(UUID())
        await chat.heard(.coachTyping(other, "xiaohun", typing: true))
        #expect(chat.coachTyping == nil)
    }

    @Test func liveEventsAddChangeAndRemove() async throws {
        let chat = store(try source([message(1, by: .member(mia), "嗨")]))
        await chat.load()
        let reacted = message(1, by: .member(mia), "嗨").reacting(try Emoji("🔥"), by: mia)
        await chat.heard(.message(squad, reacted, quoted: nil))
        #expect(chat.lines.first?.message.reactions.count == 1)
        await chat.heard(
            .message(
                squad, message(2, by: .member(mia), "回你", replyTo: id(9)), quoted: message(9, by: .member(viewer), "老的")))
        #expect(chat.message(id(9))?.text == "老的")
        await chat.heard(.deleted(squad, id(1)))
        #expect(chat.lines.map(\.message.text) == ["回你"])
    }

    @Test func reactingShowsAtOnceAndPickingItAgainTakesItBack() async throws {
        let chat = store(try source([message(1, by: .member(mia), "嗨")]))
        await chat.load()
        let fire = try Emoji("🔥")
        await chat.react(fire, on: id(1))
        #expect(chat.myReaction(on: id(1)) == fire)
        await chat.react(nil, on: id(1))
        #expect(chat.myReaction(on: id(1)) == nil)
    }

    @Test func aReactionThatCantGoOutGoesBack() async throws {
        let server = try source([message(1, by: .member(mia), "嗨")])
        let chat = store(server)
        await chat.load()
        await server.setOffline(true)
        await chat.react(try Emoji("🔥"), on: id(1))
        #expect(chat.myReaction(on: id(1)) == nil)
        #expect(chat.failure == .notSent)
    }

    @Test func theMenuOffersWhatEachMessageAllows() async throws {
        let chat = store(
            try source([
                message(1, by: .coach("xiaohun"), "教练"), message(2, by: .member(mia), "Mia"),
                message(3, by: .member(viewer), "我"),
            ]))
        await chat.load()
        #expect(chat.actions(for: id(1)) == [.reply, .copy])
        #expect(chat.actions(for: id(2)) == [.reply, .copy, .report])
        #expect(chat.actions(for: id(3)) == [.reply, .copy, .delete])
    }

    @Test func deletingAndReporting() async throws {
        let server = try source([message(1, by: .member(mia), "Mia"), message(2, by: .member(viewer), "我")])
        let chat = store(server)
        await chat.load()
        #expect(await chat.report(id(1)))
        #expect(await server.reported == [id(1)])
        await chat.delete(id(1))
        #expect(chat.lines.count == 2)
        await chat.delete(id(2))
        #expect(chat.lines.map(\.message.text) == ["Mia"])
        await chat.load()
        #expect(chat.lines.map(\.message.text) == ["Mia"])
    }

    @Test func alertsAndReading() async throws {
        let server = try source([message(1, by: .member(mia), "嗨"), message(2, by: .member(mia), "在吗")])
        let chat = store(server)
        #expect(try await server.unread(in: squad) == ChatUnread(count: 2, mentions: 0))
        await chat.load()
        await chat.markRead()
        #expect(try await server.unread(in: squad) == .none)
        await chat.setAlerts(.none)
        #expect(chat.alerts == .none)
        await chat.load()
        #expect(chat.alerts == .none)
    }

    @Test func offlineShowsAndListeningAgainComesBack() async throws {
        let server = try source([message(1, by: .member(mia), "嗨")])
        let chat = store(server)
        await chat.load()
        await server.setOffline(true)
        await chat.listen()
        #expect(chat.phase == .offline)
        #expect(chat.lines.count == 1)
        await server.setOffline(false)
        await chat.listen()
        #expect(chat.phase == .current)
    }

    @Test func reactionCountsGoMostFirst() throws {
        let fire = try Emoji("🔥")
        let heart = try Emoji("❤️")
        let reacted = message(1, by: .member(mia), "嗨").reacting(heart, by: viewer).reacting(fire, by: mia)
            .reacting(fire, by: MemberID(UUID()))
        #expect(reacted.reactionCounts.map(\.emoji) == [fire, heart])
        #expect(reacted.reactionCounts.map(\.count) == [2, 1])
    }
}

struct ChatComposerTests {
    private let characters: [MemberID: MemberCharacter]

    init() throws {
        characters = [viewer: try character("我"), mia: try character("Mia")]
    }

    @Test func theCoachComesFirstAndNeverMe() {
        let names = ChatComposer.candidates(for: "", coach: coach, characters: characters, viewer: viewer).map(\.name)
        #expect(names == ["毛头", "Mia"])
        #expect(ChatComposer.candidates(for: "", coach: nil, characters: characters, viewer: viewer).map(\.name) == ["Mia"])
        #expect(ChatComposer.candidates(for: "mi", coach: coach, characters: characters, viewer: viewer).map(\.name) == ["Mia"])
    }

    @Test func pickingReplacesWhatWasTyped() throws {
        var composer = ChatComposer()
        composer.text = "嘿 @M"
        #expect(composer.mentionQuery == "M")
        composer.pick(.member(mia, name: "Mia"))
        #expect(composer.text == "嘿 @Mia ")
        #expect(composer.mentionQuery == nil)
        composer.pick(.coach(coach))
        #expect(composer.text == "嘿 @Mia @毛头 ")
        let draft = try #require(composer.draft)
        #expect(draft.mentions == [mia])
        #expect(draft.mentionsCoach)
        #expect(draft.text.text == "嘿 @Mia @毛头")
    }

    @Test func anAtDeletedFromTheWordsDoesntCount() throws {
        var composer = ChatComposer()
        composer.pick(.coach(coach))
        composer.text = "算了"
        let draft = try #require(composer.draft)
        #expect(!draft.mentionsCoach)
        composer.text = "   "
        #expect(composer.draft == nil)
    }

    @Test func messageTextLimits() {
        #expect(MessageText(" 嗨 \n")?.text == "嗨")
        #expect(MessageText(String(repeating: "字", count: 500)) != nil)
        #expect(MessageText(String(repeating: "字", count: 501)) == nil)
    }
}
