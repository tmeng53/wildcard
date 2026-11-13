// @wildcard/feedback: 意见反馈, members' messages to us (words, screenshots and the app they
// came from, or what their coach passed on), the day's limit, and which issue each was filed as.

export {
  createPostgresFeedbackStore,
  type FeedbackTables,
} from './adapters/postgres-feedback-store.js';
export {
  AdoptionKind,
  AppInfo,
  FEEDBACK_MAX_LENGTH,
  FEEDBACK_MAX_SCREENSHOTS,
  FeedbackBody,
  FeedbackId,
  FeedbackKind,
  MemberId,
  type Adoption,
  type Feedback,
  type FeedbackSource,
  type FiledIssue,
  type FromApp,
  type FromCoach,
} from './domain/feedback.js';
export {
  FeedbackIdTakenError,
  FeedbackInvalidError,
  FeedbackLimitError,
  FeedbackMissingError,
} from './errors.js';
export type { Clock, FeedbackStore } from './ports.js';
export {
  FEEDBACK_DAILY_LIMIT,
  createFeedbackAdoptions,
  createFeedbackInbox,
  type FeedbackAdoptions,
  type FeedbackInbox,
  type SendFeedbackInput,
} from './use-cases/feedback.js';
