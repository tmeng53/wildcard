import type { Coach } from './coach.js';
import { REPLY_LIMIT } from './reply.js';
import type { CoachSettings } from './settings.js';
import { checkInLine, rosterOf, type SquadWeek } from './squad-week.js';
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
  '你会在四种时候醒来，每次的任务会告诉你是哪一种：',
  `- 有人打卡：看看这条打卡（需要的话先用 squad_week 看这周的情况），像队友在动态下面留言那样，用 reply 回一句（不超过 ${String(REPLY_LIMIT)} 字），用 react 点一个表情，或者两个都做。大多数打卡都值得回应；说得具体，接住对方说的话或练的东西，别说教、别催、别空喊加油。任务里有你最近点过的表情，换着用，别总点同一个。听到长期有用的新东西（比如新外号、新的梗）才用 edit_file 记下来。`,
  `- 有人回复你：有人在一条打卡下面回复了你说的话。看看这条打卡和你们在下面的对话，用 answer 接着回这句（不超过 ${String(REPLY_LIMIT)} 字），像在评论里聊天那样，接住对方的话。一次只回这一句。聊天里听到长期有用的新东西（新外号、新的梗、伤病、长期的习惯）才用 edit_file 记下来。`,
  `- 有人在群聊里找你：小队群聊里有人 @ 了你，或者回复了你说的话。看看群里最近的聊天，用 answer 回这一句（不超过 ${String(REPLY_LIMIT)} 字），像队友在群里聊天那样，接住对方的话，问什么答什么。一次只回这一句。聊天里听到长期有用的新东西才用 edit_file 记下来。`,
  `- 新的一天：先用 squad_week 看看小队这周，用 read_file 读读你的文件，然后整理一次记性：把该记的补上，过时的删掉，没有新的长期信息就不改文件。再用 post_note 在小队的战术板上写今天的一句（不超过 ${String(NOTE_LIMIT)} 字），全队都会看到。别重复你最近写过的。没什么值得说的，就不写。`,
  '记性：文件只记长期有用的：外号、小队的梗、长期的习惯和偏好、队员主动说过的伤病、重要的里程碑。不记单条打卡，也不记这周发生了什么，这些随时能用 squad_week 看。squad.md 记小队，memory.md 记你们之间的事，people/队员N.md 记每个人。',
  '队员看得到的话里称呼人用昵称（回复里也可以用「你」），不要写队员N，那是只有你看得到的叫法。战术板是说给全队的，不对某一个人说。',
  '文件只能用任务里列出的那些；用 read_file 读，用 edit_file 改。',
].join('\n');

/** What was said to and by the coach under one check-in, oldest first. */
export interface CoachThread {
  /** The coach's own reply to the check-in. */
  readonly reply: string;
  /** Members' replies to the coach and its answers since, oldest first. */
  readonly said: readonly {
    /** The member who wrote it, or `undefined` for the coach. */
    readonly member: string | undefined;
    readonly text: string;
    /** The reply this wake answers. */
    readonly answering?: boolean;
  }[];
}

/** The squad's chat before a message to the coach, oldest first, with the one to answer. */
export interface CoachChatTalk {
  readonly said: readonly {
    /** The member who wrote it, or `undefined` for the coach. */
    readonly member: string | undefined;
    readonly text: string;
    /** The message this wake answers. */
    readonly answering?: boolean;
  }[];
}

/** A file's size, as the task lists it. */
function sizeWords(body: string | undefined): string {
  return body === undefined || body === '' ? '空' : `${String(body.length)} 字`;
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
  chat,
  recentEmoji = [],
}: {
  readonly reason: WakeReason;
  readonly week: SquadWeek;
  /** Each file the model may use, by the path it sees, with its body when it has one. */
  readonly files: ReadonlyMap<string, string | undefined>;
  /** The squad's last 战术板 lines, newest first. */
  readonly recentNotes: readonly { readonly day: string; readonly text: string }[];
  /** On a reply's wake, what was said under its check-in. */
  readonly thread?: CoachThread;
  /** On a chat message's wake, the chat before it. */
  readonly chat?: CoachChatTalk;
  /** On a check-in's wake, the emoji the coach reacted with lately, newest first. */
  readonly recentEmoji?: readonly string[];
}): string | undefined {
  const fileList = [...files].map(([path, body]) => `${path}（${sizeWords(body)}）`).join('，');
  const filesLine = `你的文件：${fileList}。`;
  if (reason.kind === 'checkIn') {
    const checkIn = week.checkIns.find(({ id }) => id === reason.checkIn);
    if (checkIn === undefined) return undefined;
    const emoji =
      recentEmoji.length === 0
        ? '你最近没点过表情。'
        : `你最近点过的表情（新的在前）：${recentEmoji.join(' ')}`;
    return [`有人打卡：${checkInLine(checkIn, rosterOf(week))}`, emoji, filesLine].join('\n\n');
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
      .filter(({ toCoach }) => toCoach === undefined)
      .map(({ member, text }) => `- ${roster.get(member) ?? '队员'}：「${text}」`);
    return [
      `有人回复你。这条打卡：${checkInLine({ ...checkIn, comments: [] }, roster)}`,
      ...(others.length === 0 ? [] : [`这条下面别人的评论（先后顺序）：\n${others.join('\n')}`]),
      `你们在下面的对话：\n- 你：「${thread.reply}」\n${said.join('\n')}`,
      filesLine,
    ].join('\n\n');
  }
  if (reason.kind === 'chat') {
    if (chat === undefined) return undefined;
    const roster = rosterOf(week);
    const said = chat.said.map(
      ({ member, text, answering }) =>
        `- ${member === undefined ? '你' : (roster.get(member) ?? '队员')}：「${text}」${answering === true ? '（要回的这句）' : ''}`,
    );
    return [`有人在群聊里找你。群里最近的聊天（先后顺序）：\n${said.join('\n')}`, filesLine].join(
      '\n\n',
    );
  }
  const notes =
    recentNotes.length === 0
      ? '你还没在战术板上写过。'
      : `你最近写过：\n${recentNotes.map(({ day, text }) => `- ${day}：${text}`).join('\n')}`;
  return [`新的一天：${reason.day}。`, filesLine, notes].join('\n\n');
}
