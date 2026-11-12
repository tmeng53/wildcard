// @wildcard/notices: the notices each member was told (通知, the bell on 动态), kept forever,
// and how far each member has read them.

export { createPostgresBroadcastStore } from './adapters/postgres-broadcast-store.js';
export { createPostgresNoticeStore, type NoticeTables } from './adapters/postgres-notice-store.js';
export {
  BroadcastGift,
  BroadcastId,
  BroadcastStyle,
  BroadcastValue,
  isRunning,
  type Broadcast,
} from './domain/broadcast.js';
export {
  MemberId,
  NoticeId,
  NoticeSubjects,
  PushAlert,
  SquadId,
  type NewNotice,
  type NoticeKind,
  type Notice,
} from './domain/notice.js';
export { NoticeNotFoundError } from './errors.js';
export type { BroadcastStore, NoticeStore } from './ports.js';
export {
  PAGE_LIMIT,
  createNotices,
  type Broadcasts,
  type GiveGifts,
  type NoticePage,
  type Notices,
} from './use-cases/notices.js';
