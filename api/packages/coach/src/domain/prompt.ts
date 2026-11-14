import {
  challengeHow,
  challengeText,
  type DayChallengeFacts,
  type DeliveredNote,
} from './challenge.js';
import type { Coach } from './coach.js';
import { briefBlock, weekdayOf, type NoteBrief } from './member-facts.js';
import { fileRole, sliceWhole } from './memory.js';
import { LINE_LIMITS } from './line-limits.js';
import type { CoachSettings } from './settings.js';
import {
  addressedWords,
  checkInBlock,
  checkInTitle,
  dayWords,
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
 * A post's comment section as the model reads it, one line each in order: who said it (a name,
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

/** How much of each file's beginning every waking task shows, in characters. */
export const HEAD_LIMIT = 200;

/**
 * What the coach remembers on a waking day: only each file's first lines, where the night keeps
 * what matters most and longest, and how long the rest is. The rest is looked up with `recall`
 * when the talk needs it (Tracy, 2026-11-10), so the coach doesn't drag every old line into what
 * it says, or claim to remember what it doesn't.
 */
export function memoryIndex(files: ReadonlyMap<string, string | undefined>): string {
  return [
    '## 你的记性（每个文件只列开头几行，其余用 recall 查；查不到的就是不记得）',
    ...[...files].map(([path, body]) => {
      const text = body?.trim() ?? '';
      if (text === '') return `### ${path}（${fileRole(path)}）\n还是空的。`;
      const head = headOf(text);
      const rest = head.length < text.length ? `\n……（共 ${String(text.length)} 字）` : '';
      return `### ${path}（${fileRole(path)}）\n\`\`\`\n${head}\n\`\`\`${rest}`;
    }),
  ].join('\n\n');
}

/** A file's first whole lines up to `HEAD_LIMIT` characters, or the first line cut there. */
function headOf(text: string): string {
  const lines = text.split('\n');
  let head = '';
  for (const line of lines) {
    const next = head === '' ? line : `${head}\n${line}`;
    if (next.length > HEAD_LIMIT) break;
    head = next;
  }
  return head === '' ? sliceWhole(text, HEAD_LIMIT) : head;
}

/**
 * The task for one wake: what happened, the files there are, and what the coach may do this
 * time. `undefined` when there is nothing to wake for (the check-in left the squad's week).
 */
export function taskOf({
  reason,
  week,
  files,
  talks = [],
  noteTo = [],
  pastDays,
  occasions = [],
  backAgain = false,
  handover,
}: {
  readonly reason: WakeReason;
  readonly week: SquadWeek;
  /** Each file the model may use, by the path it sees, with its body when it has one. */
  readonly files: ReadonlyMap<string, string | undefined>;
  /** On a daily wake, the talk under check-ins over the last day. */
  readonly talks?: readonly DayTalk[];
  /** On a daily wake, who to write a morning note to, with their day's plan; on a welcome, the newcomer. */
  readonly noteTo?: readonly NoteBrief[];
  /** On the night's dream, the days it looks back over. */
  readonly pastDays?: PastDays;
  /** What is special about the day, such as a holiday, one line each. */
  readonly occasions?: readonly string[];
  /** Whether the coach coached this squad before, was fired and is back, and speaks for the first time since. */
  readonly backAgain?: boolean;
  /** On a waking task, whom the coach took over from and the letter it was left, if any. */
  readonly handover?: TookOver;
}): string | undefined {
  // The night tidies the whole memory, so it reads every file in full; a waking task shows each
  // file's beginning and looks the rest up.
  const filesLine = reason.kind === 'dream' ? memoryBlock(files) : memoryIndex(files);
  const whoIsWho = rosterText(week);
  const roster = rosterOf(week);
  const occasion = [...occasionBlock(occasions, backAgain), ...handoverBlock(handover)];
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
    // Nothing new since the last night: the memory stays as it is, and the night costs nothing.
    if (pastDays === undefined || pastDays.quiet) return undefined;
    return [
      `# 夜里\n今天是 ${reason.day}，${weekdayOf(reason.day)}。`,
      whoIsWho,
      ...pastDaysBlocks(pastDays, { roster, talks }),
      talksBlock(talks, { roster, span: '过去七天' }),
      filesLine,
      `## 整理记性\n${DREAM}`,
    ].join('\n\n');
  }
  // A reply's task is `replyTaskOf`'s, the morning's `noteTaskOf`'s.
  return undefined;
}

/**
 * What a welcome asks (Tracy, 2026-11-12: 让他给新人介绍自己 然后欢迎新人): one note, no
 * challenge, since a newcomer gets theirs with the next morning's note.
 */
const WELCOME = '给他写一张便条（note_to）：先介绍你自己，再欢迎他。';

/** The fact a coach hired back is told on its first wake since; what it says is its own. */
const BACK_AGAIN = '你以前带过这个小队，被换掉后，现在又被请回来了。';

/**
 * What a night is, told as what and how, never steps (Tracy, 2026-11-12: not prescriptive): the
 * week it looks back on and the memory it leaves for the morning.
 */
const DREAM = [
  '这次醒来是为了整理你的记性。上面是过去七天的动态。',
  '你的记性就是上面这几个文件，明天醒来你只记得它们。白天你只看得到每个文件的开头几行，其余要用 recall 查。rewrite_file 会把一个文件整个换成你写的样子。',
].join('\n');

/** The gift pool and who may get one, when anyone may: the give_gift tool's choices. */
export function giftBlock(
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

/** The change of coach (换教练) that brought this coach: whom it took over from and when. */
export interface TookOver {
  /** The outgoing coach's name, as the squad knows it. */
  readonly from: string;
  /** The squad's day of the change, `YYYY-MM-DD`. */
  readonly day: string;
  /** The letter the outgoing coach left the squad, which every member read. */
  readonly letter?: string;
}

/**
 * Whom the coach took over from, and the letter left with it: facts, so it can answer when
 * someone asks where the last coach went (Tracy, 2026-11-13).
 */
function handoverBlock(handover: TookOver | undefined): string[] {
  if (handover === undefined) return [];
  const { from, day, letter } = handover;
  return [
    [
      '## 你接手这个小队',
      `${day} 小队换教练，你接替了${from}。`,
      // No letter may be one still being written (交接中), so none is said, never 「没留信」.
      ...(letter === undefined ? [] : [`${from}走时给全队留了一封信，大家都看过：\n「${letter}」`]),
    ].join('\n'),
  ];
}

/** What is special about today as plain lines: the occasions, a coach back again, a handover. */
export function todayLines({
  occasions,
  backAgain,
  handover,
}: {
  readonly occasions: readonly string[];
  readonly backAgain: boolean;
  readonly handover?: TookOver | undefined;
}): string[] {
  return [
    ...occasions,
    ...(backAgain ? [BACK_AGAIN] : []),
    ...handoverBlock(handover).map((block) => block.replace(/^## 你接手这个小队\n/, '')),
  ];
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
  /**
   * The challenges the coach set over the last week up to that day, oldest first, and what each
   * member said to them: so it sees what it gave before and sets something else (Tracy, 2026-11-12).
   */
  readonly challenges?: readonly DayChallengeFacts[];
}

/** What the night's dream looks back over: the squad's days, and what the coach did in them. */
export interface PastDays {
  /** The first and last day it covers, `YYYY-MM-DD`. */
  readonly from: string;
  readonly to: string;
  /** Whether nothing happened since the night before: no post, no talk, no challenge answered. */
  readonly quiet: boolean;
  /** The squad's posts made for those days or posted on them, oldest first. */
  readonly checkIns: readonly WeekCheckIn[];
  /** The coach's 战术板 lines, oldest first. */
  readonly boards: readonly { readonly day: string; readonly text: string }[];
  /** Its notes that reached members, with how each challenge went, oldest first. */
  readonly notes: readonly DeliveredNote[];
  /** Its gifts, oldest first. */
  readonly gifts: readonly CoachGiven[];
}

export type { DeliveredNote } from './challenge.js';

/** A gift the coach gave, as it reads it back. */
export interface CoachGiven {
  readonly member: string;
  readonly piece: string;
  /** What it said with it. */
  readonly line?: string;
  readonly at: Date;
  /** Whether the member opened it (拆开), and put it on then. */
  readonly opened?: { readonly worn: boolean };
}

/** The night's look back: the posts, then what the coach wrote and gave. */
function pastDaysBlocks(
  { from, to, checkIns, boards, notes, gifts }: PastDays,
  {
    roster,
    talks,
  }: { readonly roster: ReadonlyMap<string, string>; readonly talks: readonly DayTalk[] },
): string[] {
  const talkedUnder = talkedUnderOf(talks);
  const heading = `## 过去七天（${dayWords(from)} 到 ${dayWords(to)}）小队的动态`;
  const posts =
    checkIns.length === 0
      ? `${heading}\n没人发动态。`
      : [
          heading,
          ...checkIns.map((each) =>
            checkInBlock(each, { roster, comments: talkedUnder.has(each.id) ? 'below' : true }),
          ),
        ].join('\n\n');
  const board = [
    '## 你写的战术板（全队看得到）',
    ...(boards.length === 0
      ? ['没写过。']
      : boards.map(({ day, text }) => `- ${dayWords(day)}：「${text}」`)),
  ].join('\n');
  const byMember = new Map<string, DeliveredNote[]>();
  for (const note of notes) byMember.set(note.member, [...(byMember.get(note.member) ?? []), note]);
  const noteBlocks =
    byMember.size === 0
      ? ['## 你写的便条\n没有送到谁手上的。']
      : [
          '## 你写的便条（只有收到的人看得到）',
          ...[...byMember].map(([member, theirs]) =>
            [
              `### ${roster.get(member) ?? '队员'}`,
              ...theirs.flatMap(({ day, text, challenge }) => [
                `- ${dayWords(day)}：「${text}」`,
                ...(challenge === undefined
                  ? []
                  : [
                      `  - 挑战「${challengeText(challenge.challenge)}」：${challengeHow(challenge)}`,
                    ]),
              ]),
            ].join('\n'),
          ),
        ];
  const giftBlock =
    gifts.length === 0
      ? []
      : [
          [
            '## 你送的礼物（只有收到的人知道）',
            ...gifts.map(
              ({ member, piece, line, opened }) =>
                `- ${roster.get(member) ?? '队员'}：${piece}${line === undefined ? '' : `，你说「${line}」`}；${opened === undefined ? '还没拆' : opened.worn ? '拆开了，当场穿上了' : '拆开了，没穿'}`,
            ),
          ].join('\n'),
        ];
  return [posts, board, ...noteBlocks, ...giftBlock];
}

/**
 * The posts whose comments the talk below holds in full: those point to it instead of repeating
 * them. The talk keeps only its window's comments, and an older one would otherwise be shown
 * nowhere.
 */
function talkedUnderOf(talks: readonly DayTalk[]): Set<string> {
  return new Set(
    talks
      .filter(
        ({ checkIn, said }) =>
          said.filter(({ member }) => member !== undefined).length >= checkIn.comments.length,
      )
      .map(({ checkIn }) => checkIn.id),
  );
}

/** The last day's talk, for the daily wake to remember from. */
function talksBlock(
  talks: readonly DayTalk[],
  {
    roster,
    span = '过去一天',
  }: { readonly roster: ReadonlyMap<string, string>; readonly span?: string },
): string {
  const heading = `## 和你的对话（${span}，打卡下面，先后顺序）`;
  if (talks.length === 0) return `${heading}\n没人在打卡下面和你说话。`;
  return [heading, ...talkBlocks(talks, roster)].join('\n\n');
}

/** Each post's talk: its title, then the coach's reply and what was said, one a line. */
function talkBlocks(talks: readonly DayTalk[], roster: ReadonlyMap<string, string>): string[] {
  return talks.map(({ checkIn, reply, said }) =>
    [
      `### ${checkInTitle(checkIn, roster)}`,
      ...(reply === undefined ? [] : [`- 你：「${reply}」`]),
      ...said.map(
        ({ member, text, to }) =>
          `- ${member === undefined ? '你' : `${roster.get(member) ?? '队员'}${to === undefined ? '' : addressedWords(to, { roster, coach: () => '你' })}`}：「${text}」`,
      ),
    ].join('\n'),
  );
}
