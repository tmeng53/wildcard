import { graphemeCount, mentionsBodyMetrics, mentionsSelfHarm } from '@wildcard/typed-text';
import { z } from 'zod';

import { AwardMove } from './moves.js';

// A squad's awards for a week: what the model writes for each member who checked in, the checks
// every award passes before anyone sees it, and the shape they are stored in.

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
  /** Teammates' reactions on it, by kind; a kind nobody left is left out. */
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

/** The longest title, in characters as people see them. */
export const TITLE_MAX = 6;
/** The longest award line (颁奖词). */
export const SPEECH_MAX = 24;
/** The most titles a member gets. */
export const TITLES_MAX = 3;

/** Words no award holds, besides body metrics: none ranks anyone last. */
const RANKING_WORDS = ['垫底', '最懒', '倒数'];

/**
 * The model's reply, held to this shape by structured output. Members are named by key. The
 * limits go to the model in the schema and are checked again on the answer, so a reply over
 * them is retried like any other that fails a check.
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
    topCheckIn: TopCheckIn.optional(),
  }),
]);
export type StoredAward = z.infer<typeof StoredAward>;

/** One member's awards for a squad's week. */
export interface MemberAwards {
  readonly member: MemberId;
  readonly titles: readonly Title[];
  readonly topCheckIn?: TopCheckIn;
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

/** The tries at a squad's awards that failed, and why the last one did. */
export interface Failures {
  readonly count: number;
  readonly lastError?: string;
}

/** The key a member goes by in the prompt: A, B, C…, so no id or name reaches the model. */
export const promptKey = (index: number) => String.fromCodePoint(65 + index);

/** A count in a line: 三, 两, 半, 几, 12, １２. */
const COUNT = '[一二两三四五六七八九十百几半整\\d０-９]+';

/**
 * How much someone ate, which the awards never say: 「三碗饭」, 「吃了一整只烤鸭」, 「大胃王」.
 * Eating itself is fine (「健康餐打卡王」, 「吃了一顿好的」), and so are reps, hours and sets
 * (「干了十个引体向上」, 「三盘网球」): only bowls count on their own, other units only after
 * 吃 or 炫, and 个, 块, 片, 顿 and 杯 never.
 */
const EATING_AMOUNT = new RegExp(
  [
    `${COUNT}[整大]*碗`,
    `[吃炫][了掉下光完]*(?:满满|整整|足足)?${COUNT}[整大小]*[盘份斤桶锅碟笼屉盒袋串只]`,
    '饭量|食量|胃口|大胃|干饭王|饭桶|吃撑|撑死|吃了多少|吃了好多|吃了好几|暴食|[两双三多]人份',
  ].join('|'),
  'u',
);

/**
 * True when a title or line may be shown: one line, no emoji, nothing about bodies, eating
 * amounts, ranks or self-harm.
 */
function isShowable(text: string, max: number): boolean {
  const length = graphemeCount(text);
  return (
    length >= 1 &&
    length <= max &&
    !/[\r\n\u2028\u2029]/u.test(text) &&
    !/\p{Extended_Pictographic}/u.test(text) &&
    !mentionsBodyMetrics(text) &&
    !mentionsSelfHarm(text) &&
    !EATING_AMOUNT.test(text) &&
    !RANKING_WORDS.some((word) => text.includes(word))
  );
}

/**
 * The awards a reply comes to for these members (those who checked in, in the prompt's order),
 * or `undefined` when it fails a check: a member missing, repeated or unknown, 0 or more than 3
 * titles, a title or line out of bounds, or a title used twice in the squad.
 */
export function titlesOf(
  reply: ModelReply,
  members: readonly MemberId[],
): Map<MemberId, Title[]> | undefined {
  if (reply.awards.length !== members.length) return undefined;
  const byKey = new Map(members.map((member, index) => [promptKey(index), member]));
  const result = new Map<MemberId, Title[]>();
  const seen = new Set<string>();
  for (const award of reply.awards) {
    const member = byKey.get(award.member.trim());
    if (member === undefined || result.has(member)) return undefined;
    if (award.titles.length < 1 || award.titles.length > TITLES_MAX) return undefined;
    const titles = award.titles.map(({ title, speech, move }) => ({
      title: title.trim(),
      speech: speech.trim(),
      move,
    }));
    for (const { title, speech } of titles) {
      if (!isShowable(title, TITLE_MAX) || !isShowable(speech, SPEECH_MAX)) return undefined;
      if (seen.has(title)) return undefined;
      seen.add(title);
    }
    result.set(member, titles);
  }
  return result;
}

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
