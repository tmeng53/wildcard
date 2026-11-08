// @wildcard/feedback: 意见反馈, members' messages to us (words, screenshots and the app they
// came from), the day's limit, and which issue each was filed as.

export {
  createPostgresFeedbackStore,
  type FeedbackTables,
} from './adapters/postgres-feedback-store.js';
export {
  AppInfo,
  FEEDBACK_MAX_LENGTH,
  FEEDBACK_MAX_SCREENSHOTS,
  FeedbackBody,
  FeedbackId,
  FeedbackKind,
  MemberId,
  type Feedback,
  type FiledIssue,
} from './domain/feedback.js';
export { FeedbackIdTakenError, FeedbackInvalidError, FeedbackLimitError } from './errors.js';
export type { Clock, FeedbackStore } from './ports.js';
export {
  FEEDBACK_DAILY_LIMIT,
  createFeedbackInbox,
  type FeedbackInbox,
  type SendFeedbackInput,
} from './use-cases/feedback.js';
