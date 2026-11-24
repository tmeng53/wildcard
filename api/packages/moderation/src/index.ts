// @wildcard/moderation: blocking a teammate and reporting what was posted (App Review guideline
// 1.2): the blocks' log, the reports and the issue each was filed as.

export {
  createPostgresModerationStore,
  type ModerationTables,
} from './adapters/postgres-moderation-store.js';
export {
  MemberId,
  ReportId,
  ReportKind,
  coachReplyKey,
  type Blocked,
  type FiledIssue,
  type Hidden,
  type Report,
  type ReportSnapshot,
} from './domain/moderation.js';
export {
  BlockSelfError,
  BlockedMemberMissingError,
  ReportIdTakenError,
  ReportedItemMissingError,
} from './errors.js';
export type { Clock, ModerationStore } from './ports.js';
export { createModeration, type Moderation } from './use-cases/moderation.js';
