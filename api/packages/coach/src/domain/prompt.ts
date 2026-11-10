import { writeIn } from '@wildcard/language-model';

import {
  challengeLine,
  challengeText,
  type Challenge,
  type ChallengeAnswer,
  type ChallengeCompletion,
} from './challenge.js';
import type { Coach } from './coach.js';
import { briefLine, weekdayOf, type NoteBrief } from './member-facts.js';
import { REPLY_LIMIT } from './reply.js';
import type { CoachSettings } from './settings.js';
import {
  checkInLine,
  languageOf,
  rosterOf,
  type SquadWeek,
  type WeekCheckIn,
} from './squad-week.js';
import type { WakeReason } from './wake.js';

// What the model reads: the standing instructions (the rules every coach follows, this coach's
// identity and soul, and how each kind of wake goes, each from the settings) and each wake's task. Chinese, as the coach
// speaks. The instructions are the same for every wake of a coach and come first, and each task
// holds only what changes, so the model's provider can cache that beginning (OpenAI does for a
// beginning of 1024 tokens or more) and charge less for it.

/** The longest 战术板 line, in characters; the database checks the same. */
export const NOTE_LIMIT = 60;

/** The longest line a gift comes with, in characters; the database checks the same. */
export const GIFT_LINE_LIMIT = 60;

/** On a daily wake, what the coach may give: the pool, and who may get one this week. */
export interface GiftOptions {
  readonly pool: readonly { readonly id: string; readonly description?: string }[];
  /** The members who may get a gift this week, by id, each with the gift pieces they have. */
  readonly open: ReadonlyMap<string, readonly string[]>;
}

/** The standing instructions for a coach. */
export function instructionsOf(
  settings: Pick<CoachSettings, 'rules' | 'wakes'>,
  coach: Coach,
): string {
  return [
    settings.rules,
    `你的人设：\n名字：${coach.name}\n风格：${coach.style}`,
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

/**
 * The whole comment section under one check-in, up to the comment this wake answers, oldest
 * first: every member's comment and every coach's line, this coach's and any other's (Tracy,
 * 2026-11-10: a coach reads the whole section, never only what was said to it).
 */
export interface CoachThread {
  /** The time now on the squad's clock, `11-09 周一 22:46`. */
  readonly now: string;
  readonly said: readonly {
    /** Who said it: a member by id, this coach, or another coach by its name. */
    readonly by: { readonly member: string } | 'you' | { readonly coach: string };
    readonly text: string;
    /** When a member wrote it, on the squad's clock, `11-09 周一 22:44`. */
    readonly when?: string;
    /** Which coach a member's comment replies to or @s, by its name, `你` for this one. */
    readonly to?: { readonly kind: 'reply' | 'mention'; readonly coach: string };
    /** The comment this wake answers. */
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
export function memoryBlock(files: ReadonlyMap<string, string | undefined>): string {
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
  backAgain = false,
  canSeePhotos = false,
  challenge,
  gifting,
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
  readonly yesterday?: YesterdayFacts;
  /** What is special about the day, such as a holiday, one line each. */
  readonly occasions?: readonly string[];
  /** Whether the coach coached this squad before, was fired and is back, and speaks for the first time since. */
  readonly backAgain?: boolean;
  /** On a reply's wake, whether the coach can look at the check-in's photos this time. */
  readonly canSeePhotos?: boolean;
  /** On a check-in's wake, the challenge the coach set its author today and their answer. */
  readonly challenge?: {
    readonly challenge: Challenge;
    readonly answer?: ChallengeAnswer;
    readonly reason?: string;
    readonly completion?: ChallengeCompletion;
  };
  /** On a daily wake, the gift pool and who may get one this week. */
  readonly gifting?: GiftOptions;
}): string | undefined {
  const filesLine = memoryBlock(files);
  const occasion = [...occasionBlock(occasions), ...(backAgain ? [BACK_AGAIN] : [])];
  if (reason.kind === 'checkIn') {
    const checkIn = week.checkIns.find(({ id }) => id === reason.checkIn);
    if (checkIn === undefined) return undefined;
    const emoji =
      recentEmoji.length === 0
        ? '你最近没点过表情。'
        : `你最近点过的表情（新的在前）：${recentEmoji.join(' ')}`;
    return [
      `有人打卡：${checkInLine(checkIn, rosterOf(week))}`,
      ...(challenge === undefined ? [] : [challengeLine(challenge)]),
      ...occasion,
      emoji,
      writeIn(languageOf(week, checkIn.member)),
      filesLine,
    ].join('\n\n');
  }
  if (reason.kind === 'comment') {
    const checkIn = week.checkIns.find(({ id }) => id === reason.checkIn);
    if (checkIn === undefined || thread === undefined) return undefined;
    const roster = rosterOf(week);
    const said = thread.said.map(({ by, text, when, to, answering }) => {
      const who =
        by === 'you'
          ? '你'
          : 'member' in by
            ? (roster.get(by.member) ?? '队员')
            : `${by.coach}（教练）`;
      const toWhom =
        to === undefined ? '' : to.kind === 'reply' ? `（回复${to.coach}）` : `（@${to.coach}）`;
      return `- ${when === undefined ? '' : `${when} `}${who}${toWhom}：「${text}」${answering === true ? '（要回的这句）' : ''}`;
    });
    const answering = checkIn.comments.find(({ id }) => id === reason.comment);
    // Without this the model answers from the words alone and guesses what the photos show.
    const photoCount = checkIn.photos?.length ?? 0;
    const photos =
      canSeePhotos && photoCount > 0
        ? [
            `这条打卡有 ${String(photoCount)} 张照片，你还没看过。要回的这句问到照片里的东西，就先用 look_at_photos 看。`,
          ]
        : [];
    return [
      `${answering?.toCoach === undefined && answering?.mentionsCoach !== undefined ? '有人在评论里 @ 你' : '有人回复你'}。这条打卡：${checkInLine({ ...checkIn, comments: [] }, roster)}`,
      `这条下面的评论区（先后顺序）：\n${said.join('\n')}`,
      `现在是 ${thread.now}。`,
      ...photos,
      ...occasion,
      ...(answering === undefined ? [] : [writeIn(languageOf(week, answering.member))]),
      filesLine,
    ].join('\n\n');
  }
  const roster = rosterOf(week);
  if (reason.kind === 'dream') {
    // Nothing new to learn from: the memory stays as it is, and the night costs nothing.
    if (
      talks.length === 0 &&
      (yesterday === undefined ||
        (yesterday.checkIns.length === 0 && (yesterday.challenges ?? []).length === 0))
    ) {
      return undefined;
    }
    return [
      '夜里，整理你的记性。',
      ...(yesterday === undefined ? [] : [yesterdayBlock(yesterday, roster)]),
      talksBlock(talks, roster),
      filesLine,
      DREAM,
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
  return [
    `新的一天：${reason.day}，${weekdayOf(reason.day)}。`,
    ...occasion,
    ...(yesterday === undefined ? [] : [yesterdayBlock(yesterday, roster)]),
    talksBlock(talks, roster),
    filesLine,
    notes,
    `战术板：${writeIn(week.language ?? 'zh-Hans')}`,
    noteLine,
    ...giftBlock(gifting, roster),
  ].join('\n\n');
}

/** The fact a coach hired back is told on its first wake since; what it says is its own. */
const BACK_AGAIN = '你以前带过这个小队，被换掉后，现在又被请回来了。';

/**
 * How a night goes: the whole memory brought to its truest current state, not only added to
 * (Tracy, 2026-11-08), as Claude's dreams do: merge, replace what changed, drop what stopped
 * mattering.
 */
const DREAM = [
  '把记性整理成现在最准的样子：',
  '- 从上面学到的、过很久还成立的事，记进去。',
  '- 重复的合成一条。',
  '- 前后矛盾的，留最新的。',
  '- 过时的、一时的、琐碎的，删掉。',
  '改了哪个文件，就用 rewrite_file 把那个文件整个重写一遍；没变的不用动。',
].join('\n');

/** The gift pool and who may get one, when anyone may: the give_gift tool's choices. */
function giftBlock(
  gifting: GiftOptions | undefined,
  roster: ReadonlyMap<string, string>,
): string[] {
  if (gifting === undefined || gifting.open.size === 0 || gifting.pool.length === 0) return [];
  const pool = gifting.pool.map(
    ({ id, description }) => `- ${id}${description === undefined ? '' : `：${description}`}`,
  );
  const who = [...gifting.open].map(([member, owned]) => {
    const name = roster.get(member) ?? '队员';
    return owned.length === 0 ? `- ${name}` : `- ${name}（已有：${owned.join('、')}）`;
  });
  return [`礼物清单：\n${pool.join('\n')}`, `这周还能收礼物的：\n${who.join('\n')}`];
}

/** What today is, when it is anything: facts only, never how to bring them up. */
function occasionBlock(occasions: readonly string[]): string[] {
  return occasions.length === 0 ? [] : [`今天：${occasions.join('、')}`];
}

/** What the squad did the day before: the morning notes and the dream pick up on it. */
export interface YesterdayFacts {
  readonly day: string;
  readonly checkIns: readonly WeekCheckIn[];
  /** The challenges the coach set that day and what each member said to them. */
  readonly challenges?: readonly {
    readonly member: string;
    readonly challenge: Challenge;
    readonly answer: ChallengeAnswer | undefined;
    readonly reason: string | undefined;
    readonly completion: ChallengeCompletion | undefined;
  }[];
}

/** The squad's posts of the day before, and how that day's challenges went. */
function yesterdayBlock(
  { day, checkIns, challenges = [] }: YesterdayFacts,
  roster: ReadonlyMap<string, string>,
): string {
  const posts =
    checkIns.length === 0
      ? `昨天（${weekdayOf(day)}）小队没人发动态。`
      : `昨天（${weekdayOf(day)}）小队的动态：\n${checkIns.map((each) => `- ${checkInLine(each, roster)}`).join('\n')}`;
  if (challenges.length === 0) return posts;
  const lines = challenges.map(({ member, challenge, answer, reason, completion }) => {
    const how =
      completion !== undefined
        ? '完成了'
        : answer === 'accepted'
          ? '接了，没记完成'
          : answer === 'declined'
            ? reason === undefined
              ? '没接'
              : `没接，因为「${reason}」（他只告诉了你）`
            : '没回应';
    return `- ${roster.get(member) ?? '队员'}「${challengeText(challenge)}」：${how}`;
  });
  return `${posts}\n\n昨天的挑战：\n${lines.join('\n')}`;
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
