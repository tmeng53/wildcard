// @wildcard/coach-messages: 教练消息卡, cards admins put on members' coach pages, said in the
// squad's coach's name with no model writing them: one template filled by data (its buttons'
// steps too), who got each, and what they answered on each card.

export {
  createPostgresMessageStore,
  type CoachMessageTables,
} from './adapters/postgres-message-store.js';
export {
  ButtonId,
  Card,
  CardPath,
  Link,
  MemberId,
  MessageId,
  MessageValue,
  SquadId,
  TEXT_LIMIT,
  cardsOf,
  isRunning,
  type AnswerPart,
  type Answered,
  type AnyButton,
  type AnyCard,
  type AnyStep,
  type Cast,
  type Message,
  type Stage,
  type Words,
} from './domain/message.js';
export { CoachMessageAnswerInvalidError, CoachMessageNotFoundError } from './errors.js';
export type { AnswerRow, Delivery, MessageStore } from './ports.js';
export { createCoachMessages, type CoachMessages, type MessageCard } from './use-cases/messages.js';
