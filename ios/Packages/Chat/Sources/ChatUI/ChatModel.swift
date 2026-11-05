#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import ChatDomain
import Contracts
import Foundation
import Observation

/// What the chat screen keeps besides the store: the composer, which message is lifted by a long
/// press or replied to, who-reacted, and the heads it draws.
@MainActor @Observable
public final class ChatModel {
    public let store: ChatStore
    /// The squad's name, in the header.
    public let squadName: String
    var composer = ChatComposer()
    /// The message a long press lifted, with the emoji bar and menu around it.
    var lifted: ChatMessageID?
    /// Whether ＋ on the lifted message's emoji bar opened every emoji.
    var browsing = false
    /// The message whose reactions are listed.
    var whoReacted: ChatMessageID?
    /// 「已举报」 after a report, for a moment.
    var reportedNotice: ReportedNotice?

    @ObservationIgnored private var heads: [MemberID: (outfit: Outfit, player: CharacterPlayer)] = [:]
    @ObservationIgnored private var coachHeads: [CoachID: CharacterPlayer] = [:]
    @ObservationIgnored private let now: () -> Date

    public init(store: ChatStore, squadName: String, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.squadName = squadName
        self.now = now
    }

    struct ReportedNotice: Identifiable {
        let id = UUID()
    }

    // MARK: People

    func head(of member: MemberID) -> CharacterPlayer? {
        let outfit = store.characters[member].map { Outfit($0.look) } ?? PlaceholderCharacter.lifter
        if let cached = heads[member], cached.outfit == outfit { return cached.player }
        guard let figure = try? PlaceholderCharacter.figure(wearing: outfit),
            let player = try? CharacterPlayer(figure: figure, idle: .still, now: now())
        else { return nil }
        heads[member] = (outfit, player)
        return player
    }

    /// A coach's head; nil for one this build has no art for.
    func head(ofCoach coach: CoachID) -> CharacterPlayer? {
        if let player = coachHeads[coach] { return player }
        guard CoachCharacter.exists(coach.rawValue),
            let player = try? CharacterPlayer(
                figure: CoachCharacter.figure(coach.rawValue), idle: CoachCharacter.clip(.idle, coach: coach.rawValue))
        else { return nil }
        coachHeads[coach] = player
        return player
    }

    func head(of author: ChatAuthor) -> CharacterPlayer? {
        switch author {
        case .member(let member): head(of: member)
        case .coach(let coach): head(ofCoach: coach)
        }
    }

    /// How a message names its writer: their nickname, else 队友, or the coach's name, else 教练.
    func name(of author: ChatAuthor) -> String {
        if let name = store.name(of: author) { return name }
        switch author {
        case .member: return String(localized: "队友", bundle: .module.inAppLanguage)
        case .coach: return String(localized: "教练", bundle: .module.inAppLanguage)
        }
    }

    /// The squad in a row, members then the coach: the header and the empty chat.
    var lineup: [ChatAuthor] {
        let members = store.characters.keys.sorted { $0.description < $1.description }.map(ChatAuthor.member)
        return members + (store.coaches.current.map { [ChatAuthor.coach($0.id)] } ?? [])
    }

    // MARK: Composer

    /// Whom the picker offers now, while an `@` is being typed.
    var mentionCandidates: [Mentionable] {
        guard let query = composer.mentionQuery else { return [] }
        return ChatComposer.candidates(
            for: query, coach: store.coaches.current, characters: store.characters, viewer: store.viewer)
    }

    func pick(_ mention: Mentionable) {
        composer.pick(mention)
    }

    /// 「@毛头」: puts the coach in the message.
    func mentionCoach() {
        guard let coach = store.coaches.current else { return }
        composer.pick(.coach(coach))
    }

    func reply(to id: ChatMessageID) {
        composer.replyTo = id
        lifted = nil
    }

    func send() {
        guard let draft = composer.draft else { return }
        composer.clear()
        Task { await store.send(draft) }
    }

    // MARK: Long press

    func react(_ emoji: Emoji, on id: ChatMessageID) {
        let mine = store.myReaction(on: id)
        lifted = nil
        browsing = false
        Task { await store.react(mine == emoji ? nil : emoji, on: id) }
    }

    func report(_ id: ChatMessageID) {
        lifted = nil
        Task {
            if await store.report(id) { reportedNotice = ReportedNotice() }
        }
    }

    func delete(_ id: ChatMessageID) {
        lifted = nil
        Task { await store.delete(id) }
    }
}
#endif
