import type { Coach } from './coach.js';
import { briefLine, weekdayOf, type NoteBrief } from './member-facts.js';
import { REPLY_LIMIT } from './reply.js';
import type { CoachSettings } from './settings.js';
import { checkInLine, rosterOf, saidTo, type SquadWeek, type WeekCheckIn } from './squad-week.js';
import type { WakeReason } from './wake.js';

// What the model reads: the standing instructions (the rules every coach follows, this coach's
// identity and soul, and how each kind of wake goes, all three settings) and each wake's task. Chinese, as the coach
// speaks. The instructions are the same for every wake of a coach and come first, and each task
// holds only what changes, so the model's provider can cache that beginning (OpenAI does for a
// beginning of 1024 tokens or more) and charge less for it.

/** The longest 战术板 line, in characters; the database checks the same. */
export const NOTE_LIMIT = 60;

/** The standing instructions for a coach. */
export function instructionsOf(
  settings: Pick<CoachSettings, 'rules' | 'wakes'>,
  coach: Coach,
): string {
  return [
    settings.rules,
    `你的人设：\n名字：${coach.name}\n口头禅：${coach.catchphrase}\n风格：${coach.style}`,
    coach.soul,
    wakesOf(settings.wakes),
  ].join('\n\n');
}

/**
 * How each kind of wake goes, as the settings word it: the same for every squad, so it is part of
 * the instructions, with the limits the API holds the coach to put in.
 */
function wakesOf(wakes: string): string {
  return wakes
    .replaceAll('{replyLimit}', String(REPLY_LIMIT))
    .replaceAll('{noteLimit}', String(NOTE_LIMIT));
}

/** What was said to and by the coach under one check-in, oldest first. */
export interface CoachThread {
  /** The coach's own reply to the check-in, when it wrote one. */
  readonly reply?: string;
  /** Members' replies to and @s of the coach and its answers since, oldest first. */
  readonly said: readonly {
    /** The member who wrote it, or `undefined` for the coach. */
    readonly member: string | undefined;
    readonly text: string;
    /** The reply this wake answers. */
    readonly answering?: boolean;
  }[];
}

/** One check-in's talk on a daily wake: what the coach and members said under it lately. */
export interface DayTalk {
  readonly checkIn: WeekCheckIn;
  /** The coach's own reply to it, when it said one. */
  readonly reply?: string;
  /** What was said under it lately, oldest first: members' comments and the coach's answers. */
  readonly said: readonly {
    /** The member who wrote it, or `undefined` for the coach. */
    readonly member: string | undefined;
    readonly text: string;
  }[];
}

/**
 * What the coach remembers, as every task shows it: each file with its text, the empty ones
 * named together. The coach forgets everything else between wakes, so it sees this every time.
 */
function memoryBlock(files: ReadonlyMap<string, string | undefined>): string {
  const written = [...files].filter(([, body]) => body !== undefined && body.trim() !== '');
  const empty = [...files].filter(([, body]) => body === undefined || body.trim() === '');
  return [
    '你的记性（你只记得这些）：',
    ...written.map(([path, body]) => `【${path}】\n${body ?? ''}`),
    ...(empty.length === 0 ? [] : [`还是空的：${empty.map(([path]) => path).join('，')}`]),
  ].join('\n');
}

/**
 * The task for one wake: what happened, the files there are, and what the coach may do this
 * time. `undefined` when there is nothing to wake for (the check-in left the squad's week).
 */
export function taskOf({
  reason,
  week,
  files,
  recentNotes,
  thread,
  recentEmoji = [],
  talks = [],
  noteTo = [],
  yesterday,
  occasions = [],
}: {
  readonly reason: WakeReason;
  readonly week: SquadWeek;
  /** Each file the model may use, by the path it sees, with its body when it has one. */
  readonly files: ReadonlyMap<string, string | undefined>;
  /** The squad's last 战术板 lines, newest first. */
  readonly recentNotes: readonly { readonly day: string; readonly text: string }[];
  /** On a reply's wake, what was said under its check-in. */
  readonly thread?: CoachThread;
  /** On a check-in's wake, the emoji the coach reacted with lately, newest first. */
  readonly recentEmoji?: readonly string[];
  /** On a daily wake, the talk under check-ins over the last day. */
  readonly talks?: readonly DayTalk[];
  /** On a daily wake, who to write a morning note to, with their day's plan. */
  readonly noteTo?: readonly NoteBrief[];
  /** On a daily wake, the squad's posts of the day before, oldest first. */
  readonly yesterday?: { readonly day: string; readonly checkIns: readonly WeekCheckIn[] };
  /** What is special about the day, such as a holiday, one line each. */
  readonly occasions?: readonly string[];
}): string | undefined {
  const filesLine = memoryBlock(files);
  const occasion = occasionBlock(occasions);
  if (reason.kind === 'checkIn') {
    const checkIn = week.checkIns.find(({ id }) => id === reason.checkIn);
    if (checkIn === undefined) return undefined;
    const emoji =
      recentEmoji.length === 0
        ? '你最近没点过表情。'
        : `你最近点过的表情（新的在前）：${recentEmoji.join(' ')}`;
    return [
      `有人打卡：${checkInLine(checkIn, rosterOf(week))}`,
      ...occasion,
      emoji,
      filesLine,
    ].join('\n\n');
  }
  if (reason.kind === 'comment') {
    const checkIn = week.checkIns.find(({ id }) => id === reason.checkIn);
    if (checkIn === undefined || thread === undefined) return undefined;
    const roster = rosterOf(week);
    const said = thread.said.map(
      ({ member, text, answering }) =>
        `- ${member === undefined ? '你' : (roster.get(member) ?? '队员')}：「${text}」${answering === true ? '（要回的这句）' : ''}`,
    );
    // The rest of the post's comments too, so the coach knows what the squad said around it.
    const others = checkIn.comments
      .filter((comment) => saidTo(comment) === undefined)
      .map(({ member, text }) => `- ${roster.get(member) ?? '队员'}：「${text}」`);
    const answering = checkIn.comments.find(({ id }) => id === reason.comment);
    const ownReply = thread.reply === undefined ? [] : [`- 你：「${thread.reply}」`];
    return [
      `${answering?.toCoach === undefined && answering?.mentionsCoach !== undefined ? '有人在评论里 @ 你' : '有人回复你'}。这条打卡：${checkInLine({ ...checkIn, comments: [] }, roster)}`,
      ...(others.length === 0 ? [] : [`这条下面别人的评论（先后顺序）：\n${others.join('\n')}`]),
      `你们在下面的对话：\n${[...ownReply, ...said].join('\n')}`,
      ...occasion,
      filesLine,
    ].join('\n\n');
  }
  const notes =
    recentNotes.length === 0
      ? '你还没在战术板上写过。'
      : `你最近写过：\n${recentNotes.map(({ day, text }) => `- ${day}：${text}`).join('\n')}`;
  const noteLine =
    noteTo.length === 0
      ? '今天没有要写便条的人。'
      : `今天给这些人各写一张便条：\n${noteTo.map(briefLine).join('\n')}`;
  const roster = rosterOf(week);
  return [
    `新的一天：${reason.day}，${weekdayOf(reason.day)}。`,
    ...occasion,
    ...(yesterday === undefined ? [] : [yesterdayBlock(yesterday, roster)]),
    talksBlock(talks, roster),
    filesLine,
    notes,
    noteLine,
  ].join('\n\n');
}

/** What today is, when it is anything: facts only, never how to bring them up. */
function occasionBlock(occasions: readonly string[]): string[] {
  return occasions.length === 0 ? [] : [`今天：${occasions.join('、')}`];
}

/** The squad's posts of the day before, for the morning notes to pick up on. */
function yesterdayBlock(
  { day, checkIns }: { readonly day: string; readonly checkIns: readonly WeekCheckIn[] },
  roster: ReadonlyMap<string, string>,
): string {
  if (checkIns.length === 0) return `昨天（${weekdayOf(day)}）小队没人发动态。`;
  return `昨天（${weekdayOf(day)}）小队的动态：\n${checkIns.map((each) => `- ${checkInLine(each, roster)}`).join('\n')}`;
}

/** The last day's talk, for the daily wake to remember from. */
function talksBlock(talks: readonly DayTalk[], roster: ReadonlyMap<string, string>): string {
  if (talks.length === 0) return '过去一天没人在打卡下面和你说话。';
  const blocks = talks.map(({ checkIn, reply, said }) =>
    [
      `- ${checkInLine({ ...checkIn, comments: [] }, roster)}`,
      ...(reply === undefined ? [] : [`  你：「${reply}」`]),
      ...said.map(
        ({ member, text }) =>
          `  ${member === undefined ? '你' : (roster.get(member) ?? '队员')}：「${text}」`,
      ),
    ].join('\n'),
  );
  return `过去一天打卡下面的对话（先后顺序）：\n${blocks.join('\n')}`;
}
