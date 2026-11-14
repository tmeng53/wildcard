// A squad's week as the coach sees it: who is in the squad, and what they checked in, with the
// reactions and comments on it. The model never sees a member's id: each member is their name, by
// the order they joined, with the nickname they gave their character.

import type { ReaderLanguage } from '@wildcard/language-model';

/** What a member checked in. */
export type CheckInKind = 'trained' | 'healthyMeal' | 'cheatMeal' | 'disclaimer';

export interface WeekCheckIn {
  readonly id: string;
  readonly member: string;
  /** The member's own day it counts for, `YYYY-MM-DD`. */
  readonly day: string;
  /** The member's day when they posted it, when that was after `day` (补打卡). */
  readonly postedDay?: string;
  readonly createdAt: Date;
  /**
   * The time on the member's own clock when they posted it, `HH:MM` (24-hour), when their time
   * zone is known.
   */
  readonly postedTime?: string;
  readonly kind: CheckInKind;
  /** A 练了's sport, by its name. */
  readonly sport?: string;
  readonly minutes?: number;
  /** The member's line: a caption, or a 请假条's text. */
  readonly text?: string;
  /** The name of the place the member tagged it with, never its coordinates. */
  readonly place?: string;
  /** For a 请假条: true when it is a planned rest (休息), not leave. */
  readonly restDay?: true;
  /** Its photos' storage paths, the cover first; the model sees only how many. */
  readonly photos?: readonly string[];
  /** The teammates who reacted to it, by member id, in the order they reacted. */
  readonly reactedBy: readonly string[];
  /** Teammates' comments, oldest first. */
  readonly comments: readonly WeekComment[];
  /**
   * True when it was only recorded, not posted in the 动态 (发布到动态 off): it counts, but its
   * words and photos stay with its author and the coach never answers under it.
   */
  readonly unposted?: true;
}

/** A comment on a check-in. */
export interface WeekComment {
  readonly id: string;
  readonly member: string;
  readonly text: string;
  readonly at: Date;
  /** The coach it replies to (回复 毛头：…), when it does. */
  readonly toCoach?: string;
  /** The coach it @s (@毛头), when it does. */
  readonly mentionsCoach?: string;
  /** The teammate it replies to (回复 Mia：…), by member id, when it does. */
  readonly replyTo?: string;
  /** The teammates it @s, by member id, in the order written. */
  readonly mentions?: readonly string[];
}

/**
 * Whom a comment answers or @s, as the model reads it after its writer: `（回复队员2，@队员3）`,
 * the coach by `coach` (`教练`, `你` or its name). Empty when it is said to no one in particular.
 */
export function addressedWords(
  comment: Pick<WeekComment, 'toCoach' | 'mentionsCoach' | 'replyTo' | 'mentions'>,
  {
    roster,
    coach = () => '教练',
  }: { readonly roster: ReadonlyMap<string, string>; readonly coach?: (id: string) => string },
): string {
  const name = (member: string): string => roster.get(member) ?? '队员';
  const parts = [
    ...(comment.replyTo === undefined ? [] : [`回复${name(comment.replyTo)}`]),
    ...(comment.toCoach === undefined ? [] : [`回复${coach(comment.toCoach)}`]),
    ...(comment.mentions ?? []).map((member) => `@${name(member)}`),
    ...(comment.mentionsCoach === undefined ? [] : [`@${coach(comment.mentionsCoach)}`]),
  ];
  return parts.length === 0 ? '' : `（${parts.join('，')}）`;
}

/** The coach a comment talks to, by replying to it or @-ing it, if any. */
export function saidTo(
  comment: Pick<WeekComment, 'toCoach' | 'mentionsCoach'>,
): string | undefined {
  return comment.toCoach ?? comment.mentionsCoach;
}

export interface SquadWeek {
  /** The Monday the week starts, `YYYY-MM-DD`. */
  readonly weekStart: string;
  /** The squad's name now. */
  readonly name?: string;
  /**
   * Everyone in the squad now, in the order they joined, with the language their app speaks
   * (Simplified Chinese when left out).
   */
  readonly members: readonly {
    readonly member: string;
    readonly nickname?: string;
    readonly language?: ReaderLanguage;
  }[];
  /** The squad's language, its captain's, for what the whole squad reads (the 战术板). */
  readonly language?: ReaderLanguage;
  /** The week's check-ins shared to the squad, oldest first. */
  readonly checkIns: readonly WeekCheckIn[];
}

/**
 * Each member's name for the model: their nickname, as their squadmates read it (Tracy,
 * 2026-11-14: real names, never 队员N), numbered from the second on when two share one
 * (`Mia`, `Mia2`). A member the model may not know by name (no nickname, or no AI consent) is
 * 队员N by the order they joined.
 */
export function rosterOf(week: Pick<SquadWeek, 'members'>): ReadonlyMap<string, string> {
  const taken = new Set<string>();
  return new Map(
    week.members.map(({ member, nickname }, index) => {
      const base = nickname?.trim() ?? '';
      let name = base === '' ? `队员${String(index + 1)}` : base;
      for (let count = 2; taken.has(name); count += 1) name = `${base || '队员'}${String(count)}`;
      taken.add(name);
      return [member, name];
    }),
  );
}

const KIND_WORDS: Readonly<Record<CheckInKind, string>> = {
  trained: '训练',
  healthyMeal: '健康餐',
  cheatMeal: '坦白放纵餐',
  disclaimer: '请假条',
};

/** A 请假条 the member marked as a planned rest (休息): part of the plan, not leave. */
const PLANNED_REST = '计划休息';

const WEEKDAYS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

/** `10-27 周二`, for a `YYYY-MM-DD` day. */
export function dayWords(day: string): string {
  return `${day.slice(5)} ${WEEKDAYS[new Date(`${day}T00:00:00Z`).getUTCDay()] ?? ''}`;
}

/** What a check-in was, in a few words: `游泳 45 分钟`, `健康餐`, `计划休息`. */
export function postWhat(checkIn: WeekCheckIn): string {
  if (checkIn.restDay === true) return PLANNED_REST;
  if (checkIn.kind !== 'trained') return KIND_WORDS[checkIn.kind];
  const sport = checkIn.sport ?? KIND_WORDS.trained;
  return checkIn.minutes === undefined ? sport : `${sport} ${String(checkIn.minutes)} 分钟`;
}

/** A check-in's heading as the model reads it: `11-11 周三 · 队员2 · 力量 50 分钟`. */
export function checkInTitle(checkIn: WeekCheckIn, roster: ReadonlyMap<string, string>): string {
  const what =
    checkIn.kind === 'trained' && checkIn.restDay !== true
      ? `${KIND_WORDS.trained}：${postWhat(checkIn)}`
      : postWhat(checkIn);
  return `${dayWords(checkIn.day)} · ${roster.get(checkIn.member) ?? '队员'} · ${what}`;
}

/** One comment as a list item: `- 队员2（回复队员1）：「其实是牛奶」`. */
function commentItem(comment: WeekComment, roster: ReadonlyMap<string, string>): string {
  return `- ${roster.get(comment.member) ?? '队员'}${addressedWords(comment, { roster, coach: () => '你' })}：「${comment.text}」`;
}

/**
 * One check-in as a Markdown block (Tracy, 2026-11-12: one line each was too hard to read): its
 * heading, then one fact a line, its comments under it one a line in order.
 */
export function checkInBlock(
  checkIn: WeekCheckIn,
  {
    roster,
    heading = '### ',
    comments = true,
  }: {
    readonly roster: ReadonlyMap<string, string>;
    readonly heading?: string;
    /** `false` leaves the comments out, `'below'` says they are in the talk under the posts. */
    readonly comments?: boolean | 'below';
  },
): string {
  const lines = [`${heading}${checkInTitle(checkIn, roster)}`];
  if (checkIn.postedDay !== undefined && checkIn.postedDay !== checkIn.day) {
    lines.push(
      `- 补打卡：${dayWords(checkIn.postedDay)}${checkIn.postedTime === undefined ? '' : ` 本人当地 ${checkIn.postedTime}`} 才发`,
    );
  } else if (checkIn.postedTime !== undefined) {
    lines.push(`- 本人当地 ${checkIn.postedTime} 发`);
  }
  if (checkIn.unposted === true) lines.push('- 只记录，没发动态');
  if (checkIn.place !== undefined) lines.push(`- 地点：「${checkIn.place}」`);
  if (checkIn.text !== undefined) lines.push(`- 写的：「${checkIn.text}」`);
  if (checkIn.photos !== undefined && checkIn.photos.length > 0) {
    lines.push(`- 照片：${String(checkIn.photos.length)} 张`);
  }
  if (checkIn.reactedBy.length > 0) {
    lines.push(
      `- 点了表情：${checkIn.reactedBy.map((member) => roster.get(member) ?? '队员').join('、')}`,
    );
  }
  if (comments === 'below') {
    lines.push('- 评论：见下面「和你的对话」');
  } else if (comments && checkIn.comments.length > 0) {
    lines.push(
      '- 评论（先后顺序）：',
      ...checkIn.comments.map((comment) => `  ${commentItem(comment, roster)}`),
    );
  }
  return lines.join('\n');
}

/** Who is in the squad, as a waking task lists them: everyone by name. */
export function rosterText(week: Pick<SquadWeek, 'members'>): string {
  return `## 小队的人\n${[...rosterOf(week).values()].join('、')}`;
}

/** The week as the `squad_week` tool answers it. */
export function weekText(week: SquadWeek): string {
  const roster = rosterOf(week);
  return [
    [
      '# 本周',
      ...(week.name === undefined ? [] : [`- 队名：${week.name}`]),
      `- 从 ${week.weekStart}（周一）开始`,
    ].join('\n'),
    rosterText(week),
    week.checkIns.length === 0
      ? '## 打卡\n这周还没有人打卡。'
      : ['## 打卡', ...week.checkIns.map((checkIn) => checkInBlock(checkIn, { roster }))].join(
          '\n\n',
        ),
  ].join('\n\n');
}

/**
 * The week as the model may read it: only members with a current AI consent have their words
 * in it (their nickname, check-ins and comments). The others stay on the roster as 队员N, with
 * nothing they wrote.
 */
export function consentedOnly(week: SquadWeek, consented: ReadonlySet<string>): SquadWeek {
  return {
    ...week,
    members: week.members.map((entry) =>
      consented.has(entry.member) ? entry : { member: entry.member },
    ),
    checkIns: week.checkIns
      .filter(({ member }) => consented.has(member))
      .map((checkIn) => ({
        ...checkIn,
        reactedBy: checkIn.reactedBy.filter((member) => consented.has(member)),
        comments: checkIn.comments.filter(({ member }) => consented.has(member)),
      })),
  };
}

/** The language a member's app speaks, Simplified Chinese when the week doesn't say. */
export function languageOf(week: Pick<SquadWeek, 'members'>, member: string): ReaderLanguage {
  return week.members.find((each) => each.member === member)?.language ?? 'zh-Hans';
}
