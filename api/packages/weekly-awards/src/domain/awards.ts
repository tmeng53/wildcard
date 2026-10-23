import { z } from 'zod';

import { AwardMove, EndingMove, SquadMove } from './moves.js';

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
  /** Training days in their plan for the week, and the days they trained. */
  readonly plannedDays: number;
  readonly trainedDays: number;
  /** Oldest first. */
  readonly checkIns: readonly WeekCheckIn[];
}

/** The model's middle pages of the story, the ones whose order it picks. */
export const MiddlePage = z.enum(['myWeek', 'hottest', 'meals', 'bestDisclaimer']);
export type MiddlePage = z.infer<typeof MiddlePage>;

/**
 * The squad's pages the awards may write for, as the week stood at them (no AI): each is there
 * only when the week has it.
 */
export interface SquadPages {
  /** The crown winner, and up to 2 others who finished their plan. */
  readonly podium?: { readonly champion: MemberId; readonly sides: readonly MemberId[] };
  readonly meals?: { readonly healthy: number; readonly cheat: number };
  readonly bestDisclaimer?: { readonly author: MemberId; readonly text: string };
  /** The squad's days trained against its plans; only when someone trained. */
  readonly ending?: { readonly done: number; readonly plan: number };
}

/** The longest title, in UTF-16 code units as the schema counts them: one per Chinese character. */
export const TITLE_MAX = 6;
/** The longest award line (颁奖词). */
export const SPEECH_MAX = 24;
/** The most titles a member gets. */
export const TITLES_MAX = 3;
/** The longest line on 你的一周. */
export const MY_WEEK_LINE_MAX = 12;
/** The longest line on 你最火的一条. */
export const HOTTEST_LINE_MAX = 18;
/** The longest line on 吃了. */
export const MEALS_LINE_MAX = 14;
/** The longest headline and line on the ending. */
export const HEADLINE_MAX = 4;
export const ENDING_LINE_MAX = 18;

const text = (max: number) => z.string().min(1).max(max);

/**
 * The model's reply, held to this shape by structured output. Members are named by key. The
 * limits go to the model in the schema, so the titles fit the screen.
 */
export const ModelReply = z.strictObject({
  version: z.literal(1),
  order: z.array(MiddlePage),
  awards: z.array(
    z.strictObject({
      member: z.string(),
      titles: z
        .array(
          z.strictObject({
            title: text(TITLE_MAX),
            speech: text(SPEECH_MAX),
            move: AwardMove,
          }),
        )
        .min(1)
        .max(TITLES_MAX),
      line: text(MY_WEEK_LINE_MAX).nullable(),
      hottest: z.strictObject({ line: text(HOTTEST_LINE_MAX), move: AwardMove }).nullable(),
    }),
  ),
  podium: z
    .strictObject({ speech: text(SPEECH_MAX), championMove: AwardMove, sideMove: AwardMove })
    .nullable(),
  meals: z.strictObject({ line: text(MEALS_LINE_MAX) }).nullable(),
  bestDisclaimer: z.strictObject({ authorMove: AwardMove, squadMove: SquadMove }).nullable(),
  ending: z
    .strictObject({ headline: text(HEADLINE_MAX), line: text(ENDING_LINE_MAX), move: EndingMove })
    .nullable(),
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

/** The AI's line and move on a member's 你最火的一条. */
const HottestWords = z.strictObject({ line: z.string().min(1), move: AwardMove });
export type HottestWords = z.infer<typeof HottestWords>;

const TopCheckIn = z.strictObject({
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
 * Stored JSON (`weekly_award_winners.award`): one member's titles and their most-reacted
 * check-in, as it stood at the awards.
 */
export const StoredAward = z.discriminatedUnion('version', [
  z.strictObject({
    version: z.literal(1),
    titles: z.array(Title).min(1).max(TITLES_MAX),
    /** Their line on 你的一周. */
    line: z.string().min(1).optional(),
    topCheckIn: TopCheckIn.optional(),
    hottest: HottestWords.optional(),
  }),
]);
export type StoredAward = z.infer<typeof StoredAward>;

/** One member's awards for a squad's week. */
export interface MemberAwards {
  readonly member: MemberId;
  readonly titles: readonly Title[];
  /** Their line on 你的一周. */
  readonly line?: string;
  readonly topCheckIn?: TopCheckIn;
  /** The line and move on their 你最火的一条, when they have one. */
  readonly hottest?: HottestWords;
}

/**
 * Stored JSON (`weekly_awards.story`): the AI's words on the squad's pages, each there only
 * when the week had the page and the model wrote it.
 */
export const StoryWords = z.discriminatedUnion('version', [
  z.strictObject({
    version: z.literal(1),
    /** The middle pages, every one of them once, in the model's order. */
    order: z.array(MiddlePage),
    podium: z
      .strictObject({ speech: z.string().min(1), championMove: AwardMove, sideMove: AwardMove })
      .optional(),
    meals: z.strictObject({ line: z.string().min(1) }).optional(),
    bestDisclaimer: z.strictObject({ authorMove: AwardMove, squadMove: SquadMove }).optional(),
    ending: z
      .strictObject({ headline: z.string().min(1), line: z.string().min(1), move: EndingMove })
      .optional(),
  }),
]);
export type StoryWords = z.infer<typeof StoryWords>;

/**
 * A squad's awards for a week: every member who checked in before them, in the order they
 * joined (less any account deleted since).
 */
export interface Awards {
  readonly members: readonly MemberAwards[];
  /** The AI's words on the squad's pages; none for awards given before they had any. */
  readonly story?: StoryWords;
}

/**
 * Where a squad's awards for a week stand once anything has happened to them: written, or not
 * yet, with the tries that failed (none when a member nudged before the first try).
 */
export type AwardsState =
  | { readonly status: 'given'; readonly awards: Awards }
  | { readonly status: 'failing'; readonly failures: Failures };

/** The tries at a squad's awards that failed, and why the last one did. */
export interface Failures {
  readonly count: number;
  readonly lastError?: string;
}

/** The key a member goes by in the prompt: A, B, C…, so no id or name reaches the model. */
export const promptKey = (index: number) => String.fromCodePoint(65 + index);

/** What the model wrote for one member. */
export interface MemberWords {
  readonly titles: Title[];
  readonly line?: string;
  readonly hottest?: HottestWords;
}

/**
 * The awards a reply comes to for these members (those who checked in, in the prompt's order),
 * or `undefined` when it names a member missing, repeated or unknown, or leaves a title or line
 * blank. Each is trimmed and kept on one line, as the story and stickers lay it out. The words
 * themselves are the model's: what they may say is set in the prompt. A page's words are kept
 * only for a page the week has (a member's hottest only when they have one); a blank one is
 * left out, and the page shows without it.
 */
export function wordsOf(
  reply: ModelReply,
  week: {
    readonly members: readonly MemberWeek[];
    readonly pages: SquadPages;
  },
): { readonly members: Map<MemberId, MemberWords>; readonly story: StoryWords } | undefined {
  const { members, pages } = week;
  if (reply.awards.length !== members.length) return undefined;
  const byKey = new Map(members.map((member, index) => [promptKey(index), member]));
  const result = new Map<MemberId, MemberWords>();
  for (const award of reply.awards) {
    const member = byKey.get(award.member.trim());
    if (member === undefined || result.has(member.member)) return undefined;
    const titles = award.titles.map(({ title, speech, move }) => ({
      title: oneLine(title),
      speech: oneLine(speech),
      move,
    }));
    if (titles.some(({ title, speech }) => title === '' || speech === '')) return undefined;
    const line = oneLine(award.line ?? '');
    const hottestLine = oneLine(award.hottest?.line ?? '');
    result.set(member.member, {
      titles,
      ...(line === '' ? {} : { line }),
      ...(award.hottest === null ||
      hottestLine === '' ||
      topCheckInOf(member.checkIns) === undefined
        ? {}
        : { hottest: { line: hottestLine, move: award.hottest.move } }),
    });
  }
  const written = new Set(members.map(({ member }) => member));
  const speech = oneLine(reply.podium?.speech ?? '');
  const mealsLine = oneLine(reply.meals?.line ?? '');
  const headline = oneLine(reply.ending?.headline ?? '');
  const endingLine = oneLine(reply.ending?.line ?? '');
  const story: StoryWords = {
    version: 1,
    order: [...new Set([...reply.order, ...MiddlePage.options])],
    ...(reply.podium === null ||
    speech === '' ||
    pages.podium === undefined ||
    !written.has(pages.podium.champion)
      ? {}
      : {
          podium: {
            speech,
            championMove: reply.podium.championMove,
            sideMove: reply.podium.sideMove,
          },
        }),
    ...(pages.meals === undefined || mealsLine === '' ? {} : { meals: { line: mealsLine } }),
    ...(reply.bestDisclaimer === null ||
    pages.bestDisclaimer === undefined ||
    !written.has(pages.bestDisclaimer.author)
      ? {}
      : { bestDisclaimer: reply.bestDisclaimer }),
    ...(reply.ending === null || pages.ending === undefined || headline === '' || endingLine === ''
      ? {}
      : { ending: { headline, line: endingLine, move: reply.ending.move } }),
  };
  return { members: result, story };
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
