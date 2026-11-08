import { z } from 'zod';

import { BroadcastId } from './broadcast.js';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

export const SquadId = z.uuid().brand<'SquadId'>();
export type SquadId = z.infer<typeof SquadId>;

/** A notice's id: the order they were written in, so a page's last id is where the next starts. */
export const NoticeId = z.int().positive().brand<'NoticeId'>();
export type NoticeId = z.infer<typeof NoticeId>;

/**
 * A push as it was sent: its String Catalog key and the values for its placeholders, so the
 * history says what the phone said, in the app's own words.
 */
export const PushAlert = z.strictObject({
  key: z.string().min(1),
  args: z.array(z.string()),
});
export type PushAlert = z.infer<typeof PushAlert>;

/**
 * What each kind of notice is about. A push carries its alert; what is only told in the app
 * carries ids, and the reader puts names to them when it reads, so a renamed teammate or coach
 * shows by their name now. Another kind is one more entry here, and the app skips kinds it
 * doesn't know.
 */
export const NoticeSubjects = {
  /** The 6pm daily progress push. */
  dailyProgress: z.strictObject({ version: z.literal(1), alert: PushAlert }),
  /** The weekly awards push: the week's 战报 is in. */
  weeklyAwards: z.strictObject({
    version: z.literal(1),
    alert: PushAlert,
    weekStart: z.iso.date(),
  }),
  /** A teammate (or nobody named, once they're gone) moved the squad to another scene. */
  sceneMoved: z.strictObject({
    version: z.literal(1),
    scene: z.string().min(1),
    by: MemberId.nullable(),
  }),
  /** The squad's coach answered the member's check-in: a line, an emoji or both. */
  coachReply: z.strictObject({
    version: z.literal(1),
    checkIn: z.uuid(),
    coach: z.string().min(1),
    replied: z.boolean(),
    emoji: z.string().min(1).nullable(),
  }),
  /**
   * The squad's coach left the member its morning note (便条): its words as written, since only
   * the member sees them and the note never changes.
   */
  coachNote: z.strictObject({
    version: z.literal(1),
    note: z.int().positive(),
    coach: z.string().min(1),
    day: z.iso.date(),
    text: z.string().min(1),
  }),
  /**
   * The squad changed coach and the coach that left wrote the one that took over a letter: its
   * words as written, since the letter never changes and stays readable after the next change.
   */
  coachLetter: z.strictObject({
    version: z.literal(1),
    letter: z.int().positive(),
    from: z.string().min(1),
    to: z.string().min(1),
    day: z.iso.date(),
    text: z.string().min(1),
  }),
  /**
   * A teammate commented on the member's check-in, or replied to them: the push's words as it was
   * put (sent or not, by the member's switch), and the post to open.
   */
  comment: z.strictObject({
    version: z.literal(1),
    alert: PushAlert,
    checkIn: z.uuid(),
    comment: z.uuid(),
  }),
  /**
   * The squad trained over its weekly goal `weeks` finished weeks in a row: its captain is
   * suggested a higher goal, 人均 `daysPerMember` 天, which they may set on 小队.
   */
  goalSuggestion: z.strictObject({
    version: z.literal(1),
    weeks: z.int().positive(),
    daysPerMember: z.int().min(1).max(7),
  }),
  /** A broadcast every member is told (`broadcast.ts`); its words are read when shown. */
  broadcast: z.strictObject({ version: z.literal(1), broadcast: BroadcastId }),
  /** A store opened or a prop unlocked for the member, by training or as a gift. */
  unlocked: z.strictObject({
    version: z.literal(1),
    kind: z.enum(['store', 'prop', 'piece']),
    item: z.string().min(1),
  }),
} as const;

/** A kind with what it is about, checked together. */
const KindAndSubject = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('dailyProgress'), subject: NoticeSubjects.dailyProgress }),
  z.object({ kind: z.literal('weeklyAwards'), subject: NoticeSubjects.weeklyAwards }),
  z.object({ kind: z.literal('sceneMoved'), subject: NoticeSubjects.sceneMoved }),
  z.object({ kind: z.literal('coachReply'), subject: NoticeSubjects.coachReply }),
  z.object({ kind: z.literal('coachNote'), subject: NoticeSubjects.coachNote }),
  z.object({ kind: z.literal('coachLetter'), subject: NoticeSubjects.coachLetter }),
  z.object({ kind: z.literal('unlocked'), subject: NoticeSubjects.unlocked }),
  z.object({ kind: z.literal('comment'), subject: NoticeSubjects.comment }),
  z.object({ kind: z.literal('broadcast'), subject: NoticeSubjects.broadcast }),
  z.object({ kind: z.literal('goalSuggestion'), subject: NoticeSubjects.goalSuggestion }),
]);
type KindAndSubject = z.infer<typeof KindAndSubject>;

export type NoticeKind = KindAndSubject['kind'];

/** A notice to tell, before it is written. */
export type NewNotice = KindAndSubject & {
  readonly member: MemberId;
  /** The squad it is about, if any: the squad's end takes it. */
  readonly squad?: SquadId;
};

/** A notice as written. */
export type Notice = NewNotice & { readonly id: NoticeId; readonly at: Date };

/** Checks a subject read back against its kind; `undefined` for a kind or shape this build lost. */
export function parseNotice(row: {
  readonly id: number;
  readonly member: string;
  readonly squad: string | null;
  readonly kind: string;
  readonly subject: unknown;
  readonly at: Date;
}): Notice | undefined {
  const parsed = KindAndSubject.safeParse({ kind: row.kind, subject: row.subject });
  if (!parsed.success) return undefined;
  return {
    ...parsed.data,
    id: NoticeId.parse(row.id),
    at: row.at,
    member: MemberId.parse(row.member),
    ...(row.squad === null ? {} : { squad: SquadId.parse(row.squad) }),
  };
}
