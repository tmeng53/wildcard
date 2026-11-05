import ChatDomain
import ChatUI
import Foundation

// 群聊 from 今天: the button beside 打卡 and the chat it opens.
extension MainTabs {
    /// The chat's button for the squad on home, made once the home has loaded and again for
    /// another squad.
    /// A chat push asked for the chat (`opensChat`): it opens once the home has.
    func makeChatBadge() {
        guard let home = today.home else { return }
        if chatBadge?.squad != home.squad.id {
            chatBadge = ChatBadge(source: chatSource(home), squad: home.squad.id)
        }
        if opensChat {
            opensChat = false
            openChat()
        }
    }

    /// Opens 群聊 for the squad on home, over 今天.
    func openChat() {
        guard let home = today.home else { return }
        let store = ChatStore(
            source: chatSource(home), squad: home.squad.id, viewer: home.member, now: { Date() },
            newID: { ChatMessageID(UUID()) })
        showsSquad = false
        selection = .today
        chat = ChatModel(store: store, squadName: home.squad.name)
    }
}
