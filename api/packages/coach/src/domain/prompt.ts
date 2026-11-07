import type { Coach } from './coach.js';
import { briefLine, weekdayOf, type NoteBrief } from './member-facts.js';
import { REPLY_LIMIT } from './reply.js';
import type { CoachSettings } from './settings.js';
import { checkInLine, rosterOf, saidTo, type SquadWeek, type WeekCheckIn } from './squad-week.js';
import type { WakeReason } from './wake.js';

// What the model reads: the standing instructions (the rules every coach follows, this coach's
// identity and soul, and how each kind of wake goes) and each wake's task. Chinese, as the coach
// speaks. The instructions are the same for every wake of a coach and come first, and each task
// holds only what changes, so the model's provider can cache that beginning (OpenAI does for a
// beginning of 1024 tokens or more) and charge less for it.

/** The longest 战术板 line, in characters; the database checks the same. */
export const NOTE_LIMIT = 60;

/** The standing instructions for a coach. */
export function instructionsOf(settings: Pick<CoachSettings, 'rules'>, coach: Coach): string {
  return [
    settings.rules,
    `你的人设：\n名字：${coach.name}\n口头禅：${coach.catchphrase}\n风格：${coach.style}`,
    coach.soul,
    WAKES,
  ].join('\n\n');
}

/** How each kind of wake goes: the same for every squad, so it is part of the instructions. */
const WAKES = [
  '你会在三种时候醒来，每次的任务会告诉你是哪一种：',
  `- 有人打卡：看看这条打卡（需要的话先用 squad_week 看这周的情况），像队友在动态下面留言那样，用 reply 回一句（不超过 ${String(REPLY_LIMIT)} 字），用 react 点一个表情，或者两个都做。大多数打卡都值得回应；说得具体，接住对方说的话或练的东西，别说教、别催、别空喊加油。任务里有你最近点过的表情，换着用，别总点同一个。`,
  `- 有人回复你或 @ 你：有人在一条打卡下面回复了你说的话，或在评论里 @ 了你。看看这条打卡和你们在下面的对话，用 answer 回这句（不超过 ${String(REPLY_LIMIT)} 字），像在评论里聊天那样，接住对方的话。一次只回这一句。`,
  `- 新的一天：需要的话用 squad_week 看看小队这周。任务里有过去一天大家和你的对话，过一遍，把长期有用的用 remember 记下，再用 edit_file 整理一次记性：合并重复的，删掉过时的和不该记的（吃了什么、单条动态）。然后用 post_note 在小队的战术板上写今天的一句（不超过 ${String(NOTE_LIMIT)} 字），全队都会看到。别重复你最近写过的。没什么值得说的，就不写。最后用 note_to 给任务里列出的每个人各写一张便条（不超过 ${String(NOTE_LIMIT)} 字）：只有他自己看得到，是你单独对他说的一句。任务里写着每个人今天出赛表排了什么、这周的饮食小目标、这周练了几天，还有昨天小队的动态。一张便条只说一件事：今天的训练，或者饮食小目标里的一个，或者接住他昨天发的东西。像朋友随口说的一句话，读起来顺，说得具体，每个人不一样，别每天都说饮食。记性里的事用来让话更贴他，但不说出来，也不硬塞进去。休息日就说休息日的事。没打卡的人也写，但不提他没打卡，不催。饮食小目标是他自己定的习惯（比如多喝水），可以提，这不算饮食控制；但不提体重、热量，也不评他吃了多少。`,
  '记性：你每次醒来都会忘掉以前的一切，只记得任务里「你的记性」那些。没用 remember 记下的，下次就不知道了。所以每次醒来，只要听到长期有用的新东西，就在回话的同时用 remember 记下：目标、外号、小队的梗、长期的习惯和偏好、队员主动说过的伤病、重要的里程碑、队员纠正你的事。不记吃了什么、某一顿饭、某条动态或打卡，也不记这周发生了什么，队员让你记这些也不记；这些随时能用 squad_week 看。squad.md 记小队，memory.md 记你们之间的事，people/队员N.md 记每个人。记性里已经有的不用再记。',
  '别跟队员说你记得、记着、记下了什么（「我还记着」「记住了」都不说）：记性是用的，不是说的。',
  '队员看得到的话里称呼人用昵称（回复里也可以用「你」），不要写队员N，那是只有你看得到的叫法。战术板是说给全队的，不对某一个人说。',
  '文件只能用任务里列出的那些；用 remember 记，用 edit_file 改和删。',
].join('\n');

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
