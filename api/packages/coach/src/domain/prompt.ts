import { writeIn } from '@wildcard/language-model';

import {
  challengeSection,
  challengeText,
  type Challenge,
  type ChallengeAnswer,
  type ChallengeCompletion,
} from './challenge.js';
import type { Coach } from './coach.js';
import { briefBlock, weekdayOf, type NoteBrief } from './member-facts.js';
import { fileRole } from './memory.js';
import { LINE_LIMITS } from './line-limits.js';
import type { CoachSettings } from './settings.js';
import {
  addressedWords,
  checkInBlock,
  checkInTitle,
  languageOf,
  rosterOf,
  rosterText,
  type SquadWeek,
  type WeekCheckIn,
  type WeekComment,
} from './squad-week.js';
import type { WakeReason } from './wake.js';

// What the model reads: the standing instructions (the rules every coach follows, this coach's
// identity and soul, and how each kind of wake goes, each from the settings) and each wake's task. Chinese, as the coach
// speaks. The instructions are the same for every wake of a coach and come first, and each task
// holds only what changes, so the model's provider can cache that beginning (OpenAI does for a
// beginning of 1024 tokens or more) and charge less for it.

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
    .replaceAll('{replyLimit}', String(LINE_LIMITS.reply.chinese))
    .replaceAll('{noteLimit}', String(LINE_LIMITS.note.chinese));
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
    /** The teammate a member's comment replies to, by member id. */
    readonly replyTo?: string;
    /** The teammates a member's comment @s, by member id. */
    readonly mentions?: readonly string[];
    /** The comment this wake answers. */
    readonly answering?: boolean;
  }[];
}

/**
 * A post's comment section as the model reads it, one line each in order: who said it (队员N,
 * 你, or another coach by name), when, and whom a member's comment replies to or @s.
 */
export function saidLines(
  said: CoachThread['said'],
  roster: ReadonlyMap<string, string>,
): string[] {
  return said.map(({ by, text, when, to, replyTo, mentions, answering }) => {
    const who =
      by === 'you'
        ? '你'
        : 'member' in by
          ? (roster.get(by.member) ?? '队员')
          : `${by.coach}（教练）`;
    const toWhom = addressedWords(
      {
        ...(to?.kind === 'reply' ? { toCoach: to.coach } : {}),
        ...(to?.kind === 'mention' ? { mentionsCoach: to.coach } : {}),
        ...(replyTo === undefined ? {} : { replyTo }),
        ...(mentions === undefined ? {} : { mentions }),
      },
      { roster, coach: (coach) => coach },
    );
    return `- ${when === undefined ? '' : `${when} `}${who}${toWhom}：「${text}」${answering === true ? '（要回的这句）' : ''}`;
  });
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
    /** Whom a member's comment replies to or @s. */
    readonly to?: Pick<WeekComment, 'toCoach' | 'mentionsCoach' | 'replyTo' | 'mentions'>;
  }[];
}

/**
 * What the coach remembers, as every task shows it: each file with its text, the empty ones
 * named together. The coach forgets everything else between wakes, so it sees this every time.
 */
export function memoryBlock(files: ReadonlyMap<string, string | undefined>): string {
  return [
    '## 你的记性（你只记得这些）',
    ...[...files].map(([path, body]) => {
      const text = body?.trim() ?? '';
      return `### ${path}（${fileRole(path)}）\n${text === '' ? '还是空的。' : `\`\`\`\n${text}\n\`\`\``}`;
    }),
  ].join('\n\n');
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
  /** On a daily wake, who to write a morning note to, with their day's plan; on a welcome, the newcomer. */
  readonly noteTo?: readonly NoteBrief[];
  /** On a daily wake, the squad's posts of the day before, oldest first. */
  readonly yesterday?: YesterdayFacts;
  /** What is special about the day, such as a holiday, one line each. */
  readonly occasions?: readonly string[];
  /** Whether the coach coached this squad before, was fired and is back, and speaks for the first time since. */
  readonly backAgain?: boolean;
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
  const whoIsWho = rosterText(week);
  const roster = rosterOf(week);
  const occasion = occasionBlock(occasions, backAgain);
  if (reason.kind === 'checkIn') {
    const checkIn = week.checkIns.find(({ id }) => id === reason.checkIn);
    if (checkIn === undefined) return undefined;
    const emoji =
      recentEmoji.length === 0
        ? '## 你最近点过的表情\n还没点过。'
        : `## 你最近点过的表情（新的在前）\n${recentEmoji.join(' ')}`;
    return [
      '# 有人打卡',
      checkInBlock(checkIn, { roster, heading: '## 这条打卡：' }),
      ...(challenge === undefined ? [] : [challengeSection(challenge)]),
      ...occasion,
      whoIsWho,
      emoji,
      languageSection(languageOf(week, checkIn.member)),
      filesLine,
    ].join('\n\n');
  }
  if (reason.kind === 'comment') {
    const checkIn = week.checkIns.find(({ id }) => id === reason.checkIn);
    if (checkIn === undefined || thread === undefined) return undefined;
    const answering = checkIn.comments.find(({ id }) => id === reason.comment);
    // Without this the model answers from the words alone and guesses what the photos show.
    const photoCount = checkIn.photos?.length ?? 0;
    const photos =
      photoCount > 0
        ? [
            `## 照片\n这条打卡有 ${String(photoCount)} 张照片，你还没看过。要回的这句问到照片里的东西，就先用 look_at_photos 看。`,
          ]
        : [];
    // Who wrote the line to answer, named up front: the post's author is often someone else.
    const askedBy = thread.said.find((each) => each.answering === true)?.by;
    const asker =
      askedBy !== undefined && askedBy !== 'you' && 'member' in askedBy
        ? (roster.get(askedBy.member) ?? '有人')
        : '有人';
    return [
      `# ${answering?.toCoach === undefined && answering?.mentionsCoach !== undefined ? `${asker}在评论里 @ 你` : `${asker}回复你`}`,
      checkInBlock(checkIn, { roster, heading: '## 这条打卡：', comments: false }),
      `## 评论区（先后顺序）\n${saidLines(thread.said, roster).join('\n')}`,
      `## 现在\n${thread.now}`,
      ...photos,
      ...occasion,
      whoIsWho,
      ...(answering === undefined ? [] : [languageSection(languageOf(week, answering.member))]),
      filesLine,
    ].join('\n\n');
  }
  if (reason.kind === 'joined') {
    const name = roster.get(reason.member);
    const brief = noteTo.find((each) => each.name === name);
    if (name === undefined || brief === undefined) return undefined;
    return [
      `# ${name}刚加入小队\n今天是 ${reason.day}，${weekdayOf(reason.day)}。`,
      ...occasion,
      whoIsWho,
      `## 新人\n\n${briefBlock(brief)}`,
      filesLine,
      `## 要做的\n${WELCOME}`,
    ].join('\n\n');
  }
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
      '# 夜里，整理你的记性',
      whoIsWho,
      ...(yesterday === undefined ? [] : yesterdayBlocks(yesterday, { roster, talks })),
      talksBlock(talks, roster),
      filesLine,
      `## 要做的\n${DREAM}`,
    ].join('\n\n');
  }
  const notes = [
    '## 战术板',
    `- ${writeIn(week.language ?? 'zh-Hans')}`,
    ...(recentNotes.length === 0
      ? ['- 你还没写过。']
      : ['- 你最近写过：', ...recentNotes.map(({ day, text }) => `  - ${day}：${text}`)]),
  ].join('\n');
  const noteSection =
    noteTo.length === 0
      ? '## 今天的便条\n今天没有要写便条的人。'
      : ['## 今天的便条（下面每人各写一张）', ...noteTo.map(briefBlock)].join('\n\n');
  return [
    `# 新的一天\n${reason.day}，${weekdayOf(reason.day)}。`,
    ...occasion,
    whoIsWho,
    ...(yesterday === undefined ? [] : yesterdayBlocks(yesterday, { roster, talks })),
    talksBlock(talks, roster),
    filesLine,
    notes,
    noteSection,
    ...giftBlock(gifting, roster),
  ].join('\n\n');
}

/** The language a line to one member is written in, as its own section. */
function languageSection(language: Parameters<typeof writeIn>[0]): string {
  return `## 语言\n${writeIn(language)}`;
}

/**
 * What a welcome asks (Tracy, 2026-11-12: 让他给新人介绍自己 然后欢迎新人): one note, no
 * challenge, since a newcomer gets theirs with the next morning's note.
 */
const WELCOME = '给他写一张便条（note_to）：先介绍你自己，再欢迎他。';

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
  return [`## 礼物清单\n${pool.join('\n')}`, `## 这周还能收礼物的\n${who.join('\n')}`];
}

/** What is special about today, when anything is: facts only, never how to bring them up. */
function occasionBlock(occasions: readonly string[], backAgain: boolean): string[] {
  const facts = [...occasions, ...(backAgain ? [BACK_AGAIN] : [])];
  return facts.length === 0 ? [] : [['## 今天', ...facts.map((each) => `- ${each}`)].join('\n')];
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
function yesterdayBlocks(
  { day, checkIns, challenges = [] }: YesterdayFacts,
  {
    roster,
    talks,
  }: { readonly roster: ReadonlyMap<string, string>; readonly talks: readonly DayTalk[] },
): string[] {
  // A post points to the talk below only when the talk holds every comment under it: the talk
  // keeps only the last day's, and an older comment would otherwise be shown nowhere.
  const talkedUnder = new Set(
    talks
      .filter(
        ({ checkIn, said }) =>
          said.filter(({ member }) => member !== undefined).length >= checkIn.comments.length,
      )
      .map(({ checkIn }) => checkIn.id),
  );
  const heading = `## 昨天（${weekdayOf(day)}）小队的动态`;
  const posts =
    checkIns.length === 0
      ? `${heading}\n没人发动态。`
      : [
          heading,
          ...checkIns.map((each) =>
            checkInBlock(each, { roster, comments: talkedUnder.has(each.id) ? 'below' : true }),
          ),
        ].join('\n\n');
  if (challenges.length === 0) return [posts];
  const lines = challenges.map(({ member, challenge, answer, reason, completion }) => {
    const how =
      completion !== undefined
        ? '完成了'
        : answer === 'accepted'
          ? '接了，没记完成'
          : answer === 'declined'
            ? reason === undefined
              ? '没接'
              : `没接，理由：「${reason}」（只告诉了你）`
            : '没回应';
    return `- ${roster.get(member) ?? '队员'}「${challengeText(challenge)}」：${how}`;
  });
  return [posts, ['## 昨天的挑战', ...lines].join('\n')];
}

/** The last day's talk, for the daily wake to remember from. */
function talksBlock(talks: readonly DayTalk[], roster: ReadonlyMap<string, string>): string {
  const heading = '## 和你的对话（过去一天，打卡下面，先后顺序）';
  if (talks.length === 0) return `${heading}\n没人在打卡下面和你说话。`;
  const blocks = talks.map(({ checkIn, reply, said }) =>
    [
      `### ${checkInTitle(checkIn, roster)}`,
      ...(reply === undefined ? [] : [`- 你：「${reply}」`]),
      ...said.map(
        ({ member, text, to }) =>
          `- ${member === undefined ? '你' : `${roster.get(member) ?? '队员'}${to === undefined ? '' : addressedWords(to, { roster, coach: () => '你' })}`}：「${text}」`,
      ),
    ].join('\n'),
  );
  return [heading, ...blocks].join('\n\n');
}
