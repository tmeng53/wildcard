import { typedText } from '@wildcard/typed-text';
import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/** A message's id, made by the app, so a retry saves it once. */
export const FeedbackId = z.uuid().brand<'FeedbackId'>();
export type FeedbackId = z.infer<typeof FeedbackId>;

/** What the member picked: 出问题了 (`problem`) or 提个建议 (`idea`). */
export const FeedbackKind = z.enum(['problem', 'idea']);
export type FeedbackKind = z.infer<typeof FeedbackKind>;

/** The longest message, in characters, as the app counts them. */
export const FEEDBACK_MAX_LENGTH = 1000;

/** What the member wrote: trimmed, 1 to 1000 characters, never blank. */
export const FeedbackBody = typedText({
  max: FEEDBACK_MAX_LENGTH,
  oneLine: false,
  description: 'What the member wrote: 1 to 1000 characters once trimmed.',
});

/** The most screenshots a message carries. */
export const FEEDBACK_MAX_SCREENSHOTS = 3;

/** Which app sent it, so whoever fixes it knows where to look. Never who the member is. */
export const AppInfo = z.strictObject({
  appVersion: z.string().min(1).max(20),
  build: z.string().min(1).max(20),
  os: z.string().min(1).max(40),
  device: z.string().min(1).max(40),
  language: z.string().min(1).max(20),
});
export type AppInfo = z.infer<typeof AppInfo>;

/** The app info as stored, with its own `version`. */
export const StoredAppInfo = AppInfo.extend({ version: z.literal(1) }).transform(
  ({ appVersion, build, os, device, language }): AppInfo => ({
    appVersion,
    build,
    os,
    device,
    language,
  }),
);

/** One message from a member: words, up to 3 screenshots and the app it came from. */
export interface Feedback {
  readonly id: FeedbackId;
  readonly member: MemberId;
  readonly kind: FeedbackKind;
  readonly body: string;
  /** Photo paths in the member's own folder, in the order they were added. */
  readonly screenshots: readonly string[];
  readonly app: AppInfo;
  readonly at: Date;
}

/** The issue a message was filed as. */
export interface FiledIssue {
  readonly number: number;
  readonly url: string;
}
