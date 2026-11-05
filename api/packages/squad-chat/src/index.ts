// @wildcard/squad-chat: each squad's group chat (群聊): members' messages, replies, @s,
// reactions and reports, the coach's answers and daily 战术板 line, each member's push alerts
// and how far they read, and its tables.

export { createPostgresChatStore, type ChatTables } from './adapters/postgres-chat-store.js';
export {
  ChatAlerts,
  ChatEmoji,
  MESSAGE_MAX_CHARACTERS,
  MemberId,
  MessageId,
  MessageText,
  SquadId,
  asksCoach,
  type Author,
  type ChatMessage,
} from './domain/message.js';
export {
  ChatMessageNotFoundError,
  MessageIdTakenError,
  NotYourMessageError,
  OwnMessageReportError,
  SquadNotJoinedError,
} from './errors.js';
export type { ChatMembership, ChatStore, NewMessage } from './ports.js';
export {
  PAGE_LIMIT,
  createSquadChat,
  type ChatPage,
  type SentMessage,
  type SquadChat,
} from './use-cases/squad-chat.js';
