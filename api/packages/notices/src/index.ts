// @wildcard/notices: the notices each member was told (通知, the bell on 动态), kept forever,
// and how far each member has read them.

export { createPostgresNoticeStore, type NoticeTables } from './adapters/postgres-notice-store.js';
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
export type { NoticeStore } from './ports.js';
export { PAGE_LIMIT, createNotices, type NoticePage, type Notices } from './use-cases/notices.js';
