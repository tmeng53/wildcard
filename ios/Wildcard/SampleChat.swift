import ChatDomain
import CheckInDomain
import Contracts
import Foundation

/// The sample squad's 群聊: a few lines from teammates, and 毛头 (`-uitest-coach`) answering when
/// @'d or replied to. One chat per squad for as long as the app runs, so it keeps what was sent.
@MainActor
enum SampleChat {
    private static var chats: [SquadID: InMemoryChatSource] = [:]

    static func source(for home: Home) -> any ChatSource {
        if let chat = chats[home.squad.id] { return chat }
        let characters = Dictionary(
            home.today.members.compactMap { mate in mate.character.map { (mate.member, $0) } },
            uniquingKeysWith: { first, _ in first })
        let mates = home.squad.members.filter { $0 != home.member }
        let coach = LaunchOptions.sidelineCoach ? CoachSpeaker(id: "xiaohun", name: "毛头") : nil
        let now = LaunchOptions.now()
        let lines: [(MemberID?, String)] = [
            (mates.first, String(localized: "周六谁去爬山？")),
            (mates.dropFirst().first, String(localized: "我！但我只爬到半山腰那种")),
        ]
        let messages = lines.enumerated().compactMap { index, line -> ChatMessage? in
            guard let member = line.0 else { return nil }
            return ChatMessage(
                id: ChatMessageID(UUID()), seq: index + 1, author: .member(member), kind: .text, text: line.1,
                replyTo: nil, mentions: [], mentionsCoach: false,
                sentAt: now.addingTimeInterval(Double(index - lines.count) * 60), reactions: [])
        }
        let chat = InMemoryChatSource(
            viewer: home.member, squad: home.squad.id, messages: messages, characters: characters,
            coaches: ChatCoaches(current: coach, names: coach.map { [$0.id: $0.name] } ?? [:]),
            now: { LaunchOptions.now() },
            coachAnswer: { _ in String(localized: "前一天别练腿，留着周六用。") },
            coachPause: { try? await Task.sleep(for: .seconds(1.5)) })
        chats[home.squad.id] = chat
        return chat
    }
}
