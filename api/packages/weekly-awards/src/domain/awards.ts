import { z } from 'zod';

import { AwardMove } from './moves.js';

// A squad's awards for a week: what the model writes for each member who checked in, and the
// shape they are stored in. What the awards may say is the prompt's job, not a check's.

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

export const SquadId = z.uuid().brand<'SquadId'>();
export type SquadId = z.infer<typeof SquadId>;

/** The kinds of check-in, as the check-ins module names them. */
export const CheckInKind = z.enum(['trained', 'healthyMeal', 'cheatMeal', 'disclaimer']);
export type CheckInKind = z.infer<typeof CheckInKind>;

/** A check-in as the awards are written from it. */
export interface WeekCheckIn {
  readonly id: string;
  /** The member's local day it counts for, `YYYY-MM-DD`. */
  readonly day: string;
  readonly createdAt: Date;
  readonly kind: CheckInKind;
  /** For a 练了: the listed sport's key, or the name the member gave their own. */
  readonly sport?: string | undefined;
  readonly caption?: string | undefined;
  /** For a 请假条: its text. */
  readonly text?: string | undefined;
  /** Its photos' paths, the cover first. */
  readonly photos: readonly string[];
  /** Teammates' reactions on it, by emoji; an emoji nobody left is left out. */
  readonly reactions: Readonly<Record<string, number>>;
}

/** One member's week, as the awards are written from it. */
export interface MemberWeek {
  readonly member: MemberId;
  /** Their IANA time zone, for the times of day the model is told. */
  readonly timeZone: string;
  /** Oldest first. */
  readonly checkIns: readonly WeekCheckIn[];
}

/** The longest title, in UTF-16 code units as the schema counts them: one per Chinese character. */
export const TITLE_MAX = 6;
/** The longest award line (颁奖词). */
export const SPEECH_MAX = 24;
/** The most titles a member gets. */
export const TITLES_MAX = 3;

/**
 * The model's reply, held to this shape by structured output. Members are named by key. The
 * limits go to the model in the schema, so the titles fit the screen.
 */
export const ModelReply = z.strictObject({
  version: z.literal(1),
  awards: z.array(
    z.strictObject({
      member: z.string(),
      titles: z
        .array(
          z.strictObject({
            title: z.string().min(1).max(TITLE_MAX),
            speech: z.string().min(1).max(SPEECH_MAX),
            move: AwardMove,
          }),
        )
        .min(1)
        .max(TITLES_MAX),
    }),
  ),
});
export type ModelReply = z.infer<typeof ModelReply>;

const Title = z.strictObject({
  title: z.string().min(1).meta({ description: 'The title (头衔), at most 6 characters.' }),
  speech: z.string().min(1).meta({
    description: 'Its award line (颁奖词), at most 24 characters, citing the week.',
  }),
  move: AwardMove,
});
export type Title = z.infer<typeof Title>;

/** A member's check-in with the most reactions, as it stood at the awards. */
export const TopCheckIn = z.strictObject({
  checkIn: z.uuid(),
  day: z.iso.date(),
  kind: CheckInKind,
  sport: z.string().optional(),
  caption: z.string().optional(),
  text: z.string().optional(),
  photos: z.array(z.string()).max(3),
  reactions: z.record(z.string(), z.int().min(1)),
});
export type TopCheckIn = z.infer<typeof TopCheckIn>;

/**
 * Stored JSON (`weekly_award_winners.award`): one member's titles. Not strict: rows written
 * before the frozen 战报 also carry the member's `topCheckIn`, which the 战报 now keeps itself
 * (`week_story_members`), and reading them drops it.
 */
export const StoredAward = z.discriminatedUnion('version', [
  z.object({
    version: z.literal(1),
    titles: z.array(Title).min(1).max(TITLES_MAX),
  }),
]);
export type StoredAward = z.infer<typeof StoredAward>;

/** One member's awards for a squad's week. */
export interface MemberAwards {
  readonly member: MemberId;
  readonly titles: readonly Title[];
}

/**
 * A squad's awards for a week: every member who checked in before them, in the order they
 * joined (less any account deleted since).
 */
export interface Awards {
  readonly members: readonly MemberAwards[];
}

/**
 * Where a squad's awards for a week stand once anything has happened to them: written, or not
 * yet, with the tries that failed (none when a member nudged before the first try).
 */
export type AwardsState =
  | { readonly status: 'given'; readonly awards: Awards }
  | { readonly status: 'failing'; readonly failures: Failures };

/**
 * Every title a member has won, in all their squads and weeks (周奖 on the player card): how
 * many, and the latest with how often they have won that one.
 */
export interface TitlesWon {
  readonly count: number;
  readonly latest?: { readonly title: string; readonly times: number };
}

/** Counts a member's titles from their awards, the latest week first: its first title is the latest. */
export function titlesWonOf(awards: readonly StoredAward[]): TitlesWon {
  const titles = awards.flatMap((award) => award.titles.map(({ title }) => title));
  const latest = titles[0];
  return latest === undefined
    ? { count: 0 }
    : {
        count: titles.length,
        latest: { title: latest, times: titles.filter((title) => title === latest).length },
      };
}

/** The tries at a squad's awards that failed, and why the last one did. */
export interface Failures {
  readonly count: number;
  readonly lastError?: string;
}

/** The key a member goes by in the prompt: A, B, C…, so no id or name reaches the model. */
export const promptKey = (index: number) => String.fromCodePoint(65 + index);

/**
 * The awards a reply comes to for these members (those who checked in, in the prompt's order),
 * or `undefined` when it names a member missing, repeated or unknown, or leaves a title or line
 * blank. Each is trimmed and kept on one line, as the story and stickers lay it out. The words
 * themselves are the model's: what they may say is set in the prompt.
 */
export function titlesOf(
  reply: ModelReply,
  members: readonly MemberId[],
): Map<MemberId, Title[]> | undefined {
  if (reply.awards.length !== members.length) return undefined;
  const byKey = new Map(members.map((member, index) => [promptKey(index), member]));
  const result = new Map<MemberId, Title[]>();
  for (const award of reply.awards) {
    const member = byKey.get(award.member.trim());
    if (member === undefined || result.has(member)) return undefined;
    const titles = award.titles.map(({ title, speech, move }) => ({
      title: oneLine(title),
      speech: oneLine(speech),
      move,
    }));
    if (titles.some(({ title, speech }) => title === '' || speech === '')) return undefined;
    result.set(member, titles);
  }
  return result;
}

/** The text on one line: trimmed, each line break (and the spaces around it) one space. */
const oneLine = (text: string) => text.trim().replace(/\s*[\r\n\u0085\u2028\u2029]+\s*/gu, ' ');

/**
 * A member's check-in with the most reactions, the latest on a tie (check-ins come oldest
 * first), or `undefined` when none has any.
 */
export function topCheckInOf(checkIns: readonly WeekCheckIn[]): TopCheckIn | undefined {
  let top: WeekCheckIn | undefined;
  let topCount = 0;
  for (const each of checkIns) {
    const count = Object.values(each.reactions).reduce((sum, value) => sum + value, 0);
    if (count > 0 && count >= topCount) {
      top = each;
      topCount = count;
    }
  }
  if (top === undefined) return undefined;
  return {
    checkIn: top.id,
    day: top.day,
    kind: top.kind,
    ...(top.sport === undefined ? {} : { sport: top.sport }),
    ...(top.caption === undefined ? {} : { caption: top.caption }),
    ...(top.text === undefined ? {} : { text: top.text }),
    photos: [...top.photos],
    reactions: Object.fromEntries(Object.entries(top.reactions).filter(([, count]) => count > 0)),
  };
}
