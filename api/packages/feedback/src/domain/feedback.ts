import { UNITS_PER_CHARACTER, typedText } from '@wildcard/typed-text';
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

/**
 * What the member wrote: trimmed, 1 to 1000 characters, never blank, with room for 1000 emoji,
 * since the app counts characters, not UTF-16 units.
 */
export const FeedbackBody = typedText({
  max: FEEDBACK_MAX_LENGTH,
  oneLine: false,
  rawUnits: FEEDBACK_MAX_LENGTH * UNITS_PER_CHARACTER,
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

/** Sent from 意见反馈 in the app: up to 3 screenshots and the app it came from. */
export interface FromApp {
  readonly from: 'app';
  /** Photo paths in the member's own folder, in the order they were added. */
  readonly screenshots: readonly string[];
  readonly app: AppInfo;
}

/**
 * Passed on by the squad's coach from what the member said under a post: the coach's words of
 * what they asked for are the message's `body`, and `quote` is the member's own.
 */
export interface FromCoach {
  readonly from: 'coach';
  /** The coach, by id. */
  readonly coach: string;
  readonly squad: string;
  readonly checkIn: string;
  /** The comment it was said in, when it wasn't the post itself. */
  readonly comment?: string;
  /** The member's own words the coach heard it in: the post's line or the comment. */
  readonly quote: string;
}

/** Where a message came from. */
export type FeedbackSource = FromApp | FromCoach;

/** A coach's message as stored, with its own `version`. */
export const StoredFromCoach = z
  .strictObject({
    version: z.literal(1),
    coach: z.string().min(1),
    squad: z.uuid(),
    checkIn: z.uuid(),
    comment: z.uuid().optional(),
    quote: z.string().min(1),
  })
  .transform(({ coach, squad, checkIn, comment, quote }): FromCoach => ({
    from: 'coach',
    coach,
    squad,
    checkIn,
    ...(comment === undefined ? {} : { comment }),
    quote,
  }));

/** One message from a member: their words (or their coach's of what they asked for). */
export interface Feedback {
  readonly id: FeedbackId;
  readonly member: MemberId;
  readonly kind: FeedbackKind;
  readonly body: string;
  readonly source: FeedbackSource;
  readonly at: Date;
}

/** The issue a message was filed as. */
export interface FiledIssue {
  readonly number: number;
  readonly url: string;
}

/**
 * What we used a message as: a bug we confirmed is real (reproduced or fixed), or an idea whose
 * change shipped. Only an admin says so, after checking; nothing adopts on its own.
 */
export const AdoptionKind = z.enum(['bug', 'idea']);
export type AdoptionKind = z.infer<typeof AdoptionKind>;

/** A message we used, once a message, and the admin who said so. Never changed. */
export interface Adoption {
  readonly feedback: FeedbackId;
  /** Who sent the message: whom it thanks. */
  readonly member: MemberId;
  readonly kind: AdoptionKind;
  readonly admin: MemberId;
  readonly at: Date;
}
