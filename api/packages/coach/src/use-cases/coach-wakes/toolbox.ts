import { z } from 'zod';

import {
  editBody,
  FILE_LIMIT,
  fileRole,
  recallLines,
  shownPathOf,
  shownPaths,
  storedPathOf,
  type StoredPath,
} from '../../domain/memory.js';
import {
  Challenge,
  CHALLENGE_AMOUNT_MAX,
  challengeHow,
  challengeText,
  type DayChallengeFacts,
} from '../../domain/challenge.js';
import { fitsLine, limitWords, type LineKind } from '../../domain/line-limits.js';
import type { GiftOptions } from '../../domain/prompt.js';
import { PostNumbers } from '../../domain/reply-task.js';
import { CoachEmoji, lineProblemAmong } from '../../domain/reply.js';
import {
  checkInBlock,
  weekText,
  type SquadWeek,
  type WeekCheckIn,
} from '../../domain/squad-week.js';
import type { WakeReason, WakeStep } from '../../domain/wake.js';
import type { CoachMemes, CoachTool, ToolAnswer } from '../../ports.js';
import {
  memberOf,
  namesOf,
  peopleOf,
  personOf,
  userIdIn,
  type Roster,
} from '../../domain/roster.js';

// What the coach thinks out before a line, as required fields ahead of the line itself (Tracy,
// 2026-11-14: a structure to think in, so it gets simple things right). Fields are generated in
// order, so the line is written with its thinking already there. Kept only in coach_wake_steps.
const privately = '只有你自己看得到';
const toneOf = z
  .string()
  .describe(
    `换成你：以你的性格，这件事里你最在意哪一点，你是什么心情，你想怎么接。要跟 anyone_would_say 那句明显不一样，不是换个说法。看法来自你是谁，不来自比喻和行话。${privately}`,
  );
const plainDraft = z.string().describe(`这句要让他知道什么，用大白话写一遍。${privately}`);
const anyoneWouldSay = z
  .string()
  .describe(
    `随便哪个教练看到这件事都会说的那句话，和谁都会顺手用上的那个说法或玩笑。写出来是为了不说它。${privately}`,
  );
const factsUsed = z
  .array(
    z.object({
      about_user_id: z
        .string()
        .nullable()
        .describe('这件事是谁的：他的 user_id。不是某一个人的事（日子、天气、全队的事）填 null'),
      fact: z.string().describe('这件事，和它从哪来（任务里写的，或者哪个工具查到的）'),
    }),
  )
  .describe(
    `这句要用到的事实，一件一条，各是谁的。只列真要用的；不是对方的事，别当成他的说。${privately}`,
  );

/** Why the facts a line is built on can't stand: one names a user_id nobody has. */
function factsProblem(
  facts: readonly { readonly about_user_id: string | null }[],
  roster: Roster,
): string | undefined {
  for (const { about_user_id: about } of facts) {
    if (about !== null && memberOf(roster, about) === undefined) {
      return `facts 里的 about_user_id「${about}」不是小队里的人。小队的人：${peopleOf(roster)}。`;
    }
  }
  return undefined;
}

/** Why a line members read can't be said: it holds a user_id, or breaks the line's own rules. */
function sayingProblem(
  line: string,
  { kind, roster }: { readonly kind: LineKind; readonly roster: Roster },
): string | undefined {
  const leaked = userIdIn(roster, line);
  return leaked === undefined
    ? lineProblemAmong(line, { kind, names: namesOf(roster) })
    : `这句里写了 user_id「${leaked}」。user_id 只在工具参数里用，给人看的话里只写名字。`;
}

/** Arguments a tool refused, which may hold members' words: every text by its length only. */
function lengthsOf(input: unknown): unknown {
  if (typeof input === 'string') return `（${String(input.length)} 字）`;
  if (Array.isArray(input)) return `（${String(input.length)} 条）`;
  if (typeof input !== 'object' || input === null) return input;
  return Object.fromEntries(Object.entries(input).map(([key, value]) => [key, lengthsOf(value)]));
}

/** A line's thinking, kept by its length only. */
function thoughtLengths(
  input: Readonly<Record<string, unknown>>,
  fields: readonly string[],
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(input).map(([key, value]) => [
      key,
      !fields.includes(key)
        ? value
        : typeof value === 'string'
          ? `（${String(value.length)} 字）`
          : Array.isArray(value)
            ? `（${String(value.length)} 条）`
            : value,
    ]),
  );
}

/** What a wake's tools change, kept in memory until the run ends and saved together then. */
export interface WakeDraft {
  /** The squad's files, by stored path, as the run left them. */
  readonly files: Map<StoredPath, string>;
  /** The files the run changed. */
  readonly changed: Set<StoredPath>;
  /** The 战术板 line the run posted, on a daily wake. */
  note: string | undefined;
  /**
   * The morning note (便条) the run wrote to each member, by member id, on a daily wake, with the
   * day's challenge it sets, if any.
   */
  readonly memberNotes: Map<string, { readonly text: string; readonly challenge?: Challenge }>;
  /**
   * The day's challenge set for each member, by member id, on a daily wake, before the coach
   * writes its notes: each goes on that member's note.
   */
  readonly challenges: Map<string, Challenge>;
  /** The gift the run gives each member, by member id, on a daily wake. */
  readonly gifts: Map<string, { readonly piece: string; readonly line: string }>;
  /** What the run said to the check-in, on its wake. */
  reply: string | undefined;
  /** Whom that line @s, by member id. */
  replyMentions: readonly string[];
  /** The emoji the run reacted to the check-in with, on its wake. */
  reaction: CoachEmoji | undefined;
  /** What the run answered a member's reply to it, on that reply's wake. */
  answer: string | undefined;
  /** Whom that answer @s, by member id. */
  answerMentions: readonly string[];
  /**
   * What the member the wake answers asked of the app, which the run passes on to the team, on a
   * check-in's or a reply's wake.
   */
  feedback: { readonly kind: 'problem' | 'idea'; readonly text: string } | undefined;
  /** Every tool call of the run, in order. */
  readonly steps: WakeStep[];
}

/**
 * A tool whose arguments are checked against its own shape before it runs, and whose every call
 * is kept in the draft's steps: a read's answer by its length only, and a file edit's text by its
 * length, since they hold members' words kept elsewhere.
 */
function defineTool<Shape extends z.ZodObject>(
  steps: WakeStep[],
  tool: {
    readonly name: string;
    readonly description: string;
    readonly parameters: Shape;
    /** A read: its answer is kept by its length only. */
    readonly reads?: boolean;
    /** What of its arguments is kept, when not all of them: they may hold members' words. */
    readonly kept?: (input: z.infer<Shape>) => unknown;
    run(input: z.infer<Shape>): string | Promise<string>;
  },
): CoachTool {
  return {
    name: tool.name,
    description: tool.description,
    parameters: tool.parameters,
    run: async (input) => {
      const parsed = tool.parameters.safeParse(input);
      const output = parsed.success
        ? await tool.run(parsed.data)
        : `参数不对：${z.prettifyError(parsed.error)}`;
      steps.push({
        tool: tool.name,
        input:
          tool.kept === undefined
            ? input
            : parsed.success
              ? tool.kept(parsed.data)
              : lengthsOf(input),
        output: tool.reads === true && parsed.success ? `（${String(output.length)} 字）` : output,
      });
      return output;
    },
  };
}

/**
 * A line that @s teammates (by user_id): each gets 「@昵称」 at the front unless the line already
 * has it, and their member ids, or why it can't be said.
 */
export function mentioning(
  {
    line,
    at,
    to,
  }: {
    readonly line: string;
    /** The user_ids to @. */
    readonly at: readonly string[];
    /** Whom the line answers, by member id: they get it anyway, so they are never @'d. */
    readonly to?: string | undefined;
  },
  { week, roster }: { readonly week: Pick<SquadWeek, 'members'>; readonly roster: Roster },
): { readonly line: string; readonly mentions: readonly string[] } | string {
  const mentions: string[] = [];
  const prefix: string[] = [];
  let said = line;
  const nicknameOf = (member: string): string | undefined =>
    week.members.find((each) => each.member === member)?.nickname;
  for (const userId of new Set(at.map((each) => each.trim()))) {
    const member = memberOf(roster, userId);
    if (member !== undefined && member === to) continue;
    const nickname = member === undefined ? undefined : nicknameOf(member);
    if (member === undefined || nickname === undefined) {
      const known = [...roster.keys()].filter((each) => nicknameOf(each) !== undefined);
      return known.length === 0
        ? `mention_user_ids 里的「${userId}」@ 不了；现在没有能 @ 的队友。`
        : `mention_user_ids 里的「${userId}」@ 不了；能 @ 的是：${peopleOf(roster, known)}。`;
    }
    mentions.push(member);
    if (said.includes(`@${nickname}`)) {
      // 「@Miao」 isn't an @ of Mia: what a longer teammate's name goes on with is left as is.
      const longer = week.members.flatMap(({ nickname: other }) =>
        other !== undefined && other !== nickname && other.startsWith(nickname)
          ? [other.slice(nickname.length)]
          : [],
      );
      said = spacedAfter(said, { tag: `@${nickname}`, longer });
    } else prefix.push(`@${nickname} `);
  }
  return { line: prefix.join('') + said, mentions };
}

/**
 * `line` with a space after each `tag` not already followed by one, so the app sees where the
 * name ends; never inside a longer name, which goes on with one of `longer`.
 */
function spacedAfter(
  line: string,
  { tag, longer }: { readonly tag: string; readonly longer: readonly string[] },
): string {
  const [first = '', ...rest] = line.split(tag);
  const spaced = (after: string): boolean =>
    after === '' || /^\s/u.test(after) || longer.some((more) => after.startsWith(more));
  return rest.reduce((said, after) => `${said}${tag}${spaced(after) ? '' : ' '}${after}`, first);
}

/** The `at` parameter of a line the coach says under a check-in. */
const mentionUserIds = z
  .array(z.string())
  .max(3)
  .describe(
    '要 @ 的队友的 user_id，不 @ 谁就填 []。被 @ 的人会收到推送，句首自动加上「@名字」。你回的那个人本来就收得到，不用 @',
  );

/**
 * The tools a coach has on a wake: reading the squad's week, remembering and tidying its files,
 * on a daily wake posting the 战术板 line, on a check-in's wake replying and reacting to it, and
 * on a reply's wake answering it. Nothing is saved until the run ends.
 */
export function toolbox({
  week,
  roster,
  coach,
  draft,
  kind,
  photos,
  facts,
  pastWeek,
  memes,
  commentsOf,
  noteTo = [],
  gifting,
  to,
  relaying = 'nothing',
  numbers = new PostNumbers(),
  challenges,
}: {
  /** On a check-in's or a reply's wake, today's challenges in the squad, looked up on demand. */
  readonly challenges?: () => Promise<readonly DayChallengeFacts[]>;
  /** Each post's number for the run, the same as the task's. */
  readonly numbers?: PostNumbers;
  readonly week: SquadWeek;
  readonly roster: Roster;
  /** The coach at work, by id: its own page is `me.md`. */
  readonly coach: string;
  readonly draft: WakeDraft;
  readonly kind: WakeReason['kind'];
  /** The URLs of the photos of the check-in this wake is about, when it has any to look at. */
  readonly photos?: () => Promise<readonly string[]>;
  /** The members' stats and this week's plans, as the model reads them. */
  readonly facts?: () => Promise<string>;
  /** A week before this one, as the model may read it. */
  readonly pastWeek: (weeksAgo: number) => Promise<SquadWeek>;
  /** What was said under a post, one line each, the coach's own lines too. */
  readonly commentsOf: (checkIn: WeekCheckIn) => Promise<readonly string[]>;
  /** The memes in use now, for humour. */
  readonly memes?: CoachMemes;
  /** On a daily wake, the members the coach may write a morning note to, by id. */
  readonly noteTo?: readonly string[];
  /** On a daily wake, the gift pool and who may get a gift this week. */
  readonly gifting?: GiftOptions;
  /** Whom a line on this wake answers, by member id: the post's author or the replier. */
  readonly to?: string | undefined;
  /**
   * On a check-in's or a reply's wake, whether the member it answers said something there in
   * their own words, which the coach may pass on to the team (`heard`), said nothing
   * (`nothing`), or passing feedback on is off (`off`), when the tool isn't offered.
   */
  readonly relaying?: 'heard' | 'nothing' | 'off';
}): CoachTool[] {
  const view = { roster, coach };
  const unknownPath = (path: string) =>
    `没有 ${path} 这个文件。能用的是：${shownPaths(view).join('、')}（people/ 后面是那个人的 user_id）。`;
  const pathHelp = `文件路径：${['squad.md', 'memory.md', 'me.md'].map((path) => `${path}（${fileRole(path)}）`).join('，')}，people/<user_id>.md（那一个队员）`;
  // Each week is read at most once a run, however many tools ask for it.
  const weeks = new Map<number, Promise<SquadWeek>>([[0, Promise.resolve(week)]]);
  const weekAgo = (weeksAgo: number): Promise<SquadWeek> => {
    const read = weeks.get(weeksAgo) ?? pastWeek(weeksAgo);
    weeks.set(weeksAgo, read);
    return read;
  };
  const tools = [
    defineTool(draft.steps, {
      name: 'squad_week',
      reads: true,
      description:
        '读小队一整周的动态。返回小队的人（名字和 user_id），和这一周每条动态：谁发的、是什么、写了什么、谁点了表情、下面的评论。时间都是发的人自己当地的时间。要看全队这一周怎么样时用；只关心一个人就用 member_posts，更省。',
      parameters: z.object({
        weeks_ago: z
          .number()
          .int()
          .min(0)
          .max(4)
          .nullable()
          .describe('看几周前：0 或 null 是这周，最多 4'),
      }),
      run: async ({ weeks_ago: weeksAgo }) => weekText(await weekAgo(weeksAgo ?? 0)),
    }),
    ...postTools(draft.steps, { roster, weekAgo, commentsOf, numbers }),
    defineTool(draft.steps, {
      name: 'recall',
      reads: true,
      description:
        '查你的记性文件。返回对上的每一行，前面带着它在哪个文件；一次最多约 2000 字，没列完会告诉你。说到一个人以前的事、你们之间的事，或者要说「记得」之前，先查。查不到就是不记得，不要当成记得。',
      parameters: z.object({
        path: z.string().nullable().describe(`只查这一个文件，null 查全部。${pathHelp}`),
        query: z
          .string()
          .nullable()
          .describe('要找的词，几个词用空格隔开，对上一个就算；null 列出整个文件'),
      }),
      run: ({ path, query }) => {
        // Every file the task lists, an empty one too, so recall never says a listed file is missing.
        const shown = new Map(shownPaths(view).map((name) => [name, '']));
        for (const [stored, body] of draft.files) {
          const name = shownPathOf(stored, view);
          if (name !== undefined) shown.set(name, body);
        }
        return recallLines(shown, {
          ...(path === null ? {} : { path }),
          ...(query === null ? {} : { query }),
        });
      },
    }),
    defineTool(draft.steps, {
      name: 'remember',
      description:
        '往记性文件里加一件事，一次一件，一句话；加在文件末尾。你每次醒来只记得这些文件，所以过很久还成立、会改变你以后怎么跟他说话的事（喜好、习惯、他想你怎么跟他说话、你答应了他什么）要当场记。今天就过去的事、文件里已经有的（拿不准先 recall）不记。',
      parameters: z.object({
        path: z.string().describe(`记到哪个文件。${pathHelp}`),
        fact: z.string().describe('要记的这件事，一句话；说到人写名字，不写 user_id'),
      }),
      kept: ({ path, fact }) => ({ path, fact: `（${String(fact.length)} 字）` }),
      run: ({ path, fact }) => {
        const stored = storedPathOf(path, view);
        if (stored === undefined) return unknownPath(path);
        const line = fact.trim();
        if (line === '') return 'fact 是空的，写上要记的事。';
        const edited = editBody(draft.files.get(stored) ?? '', { find: '', replace: `- ${line}` });
        if (!edited.ok) return edited.why;
        draft.files.set(stored, edited.body);
        draft.changed.add(stored);
        return `记下了，在 ${path}。`;
      },
    }),
    defineTool(draft.steps, {
      name: 'edit_file',
      description:
        '改一个记性文件里的一处：把 find 的原文换成 replace，replace 是空字符串就是删掉。用来改掉过时的、合并重复的。find 必须照抄文件里的原文（先 recall 查出来），而且在文件里正好出现一次；对不上会告诉你为什么。',
      parameters: z.object({
        path: z.string().describe(pathHelp),
        find: z.string().describe('要换掉的原文，照抄'),
        replace: z.string().describe('换成的新内容；空字符串是删掉'),
      }),
      // A file's text may be a member's words, kept in the file only as long as the file has it.
      kept: ({ path, find, replace }) => ({
        path,
        find: `（${String(find.length)} 字）`,
        replace: `（${String(replace.length)} 字）`,
      }),
      run: ({ path, find, replace }) => {
        const stored = storedPathOf(path, view);
        if (stored === undefined) return unknownPath(path);
        const edited = editBody(draft.files.get(stored) ?? '', { find, replace });
        if (!edited.ok) return edited.why;
        draft.files.set(stored, edited.body);
        draft.changed.add(stored);
        return `已改好，${path} 现在 ${String(edited.body.length)} 字。`;
      },
    }),
  ];
  // A reply and the morning's notes read the posts they need by number and remember as they go;
  // the week's whole list, the stats and tidying the files are the night's (Tracy, 2026-11-14).
  const replying = kind === 'checkIn' || kind === 'comment';
  if (replying || kind === 'daily') {
    const kept = tools.filter(({ name }) => name !== 'squad_week' && name !== 'edit_file');
    tools.length = 0;
    tools.push(...kept);
  }
  if (facts !== undefined && !replying && kind !== 'daily') {
    tools.push(
      defineTool(draft.steps, {
        name: 'member_stats',
        reads: true,
        description:
          '读全队每个人的长期数据。每人一段：从加入到现在一共练了几天，健康餐、放纵餐、请假条各几次，最常练的运动，拿过几个周奖，还有这周的出赛表。要说一个人长期怎么样、或者这周计划了什么时用；他最近具体发了什么用 member_posts。',
        parameters: z.object({}),
        run: async () => {
          try {
            return await facts();
          } catch {
            return '数据现在查不到，先不提。';
          }
        },
      }),
    );
  }
  if (memes !== undefined) {
    tools.push(
      defineTool(draft.steps, {
        name: 'memes',
        reads: true,
        description:
          '读梗库：现在大家在玩的梗，每条是原话、意思和来历。想要幽默的灵感时看一眼；正好合适才用，对不上就不用。',
        parameters: z.object({}),
        run: async () => {
          let list: Awaited<ReturnType<CoachMemes>>;
          try {
            list = await memes();
          } catch {
            return '梗库现在查不到，先不用。';
          }
          if (list.length === 0) return '梗库现在是空的。';
          return list
            .map(
              ({ phrase, meaning, background }) => `- 「${phrase}」：${meaning}（${background}）`,
            )
            .join('\n');
        },
      }),
    );
  }
  // Before each kind's own tools, and on every such wake, so the list stays the same and cached.
  if ((kind === 'checkIn' || kind === 'comment') && relaying !== 'off') {
    tools.push(relayFeedback(draft, relaying === 'heard'));
  }
  if (kind === 'daily') {
    tools.push(
      defineTool(draft.steps, {
        name: 'post_note',
        description: `在小队的战术板上写今天的一句。全队每个人都看得到，挂一整天。一天只有一句，再调用会换掉上一句。${limitWords('note')}；超了会告诉你超了多少。前面几个参数是你写之前想的，${privately}，按顺序填完再写 text。`,
        parameters: z.object({
          topic: z.string().describe(`今天这句说哪件事，为什么是这件。${privately}`),
          facts: factsUsed,
          plain_draft: plainDraft,
          anyone_would_say: anyoneWouldSay,
          tone: toneOf,
          text: z
            .string()
            .describe(
              '战术板上的这一句：按 tone 里你的看法来说，是你才会说的话；plain_draft 的意思要在，读的人不用想就懂',
            ),
        }),
        kept: (input) =>
          thoughtLengths(input, ['topic', 'facts', 'plain_draft', 'anyone_would_say', 'tone']),
        run: ({ facts, text }) => {
          const wrong = factsProblem(facts, roster);
          if (wrong !== undefined) return wrong;
          const line = text.trim();
          const problem = sayingProblem(line, { kind: 'note', roster });
          if (problem !== undefined) return problem;
          const replaced = draft.note !== undefined;
          draft.note = line;
          return replaced ? '已换成这句。' : '已写上战术板。';
        },
      }),
      noteTool(draft, { roster, noteTo, welcome: false }),
    );
  }
  if (
    kind === 'daily' &&
    gifting !== undefined &&
    gifting.open.size > 0 &&
    gifting.pool.length > 0
  ) {
    tools.push(giveGift(draft, { roster, gifting }));
  }
  if (kind === 'joined') tools.push(noteTool(draft, { roster, noteTo, welcome: true }));
  if (kind === 'dream') {
    tools.push(
      defineTool(draft.steps, {
        name: 'rewrite_file',
        description: `把一个记性文件整个换成你新写的内容：要留的照写进去，没写的就没了。夜里整理记性时用，把最要紧的放在最前面（白天只看得到每个文件的开头几行）。只改一两处用 edit_file。不超过 ${String(FILE_LIMIT)} 字。`,
        parameters: z.object({
          path: z.string().describe(pathHelp),
          body: z
            .string()
            .describe('这个文件的全部新内容；空字符串是清空。说到人写名字，不写 user_id'),
        }),
        kept: ({ path, body }) => ({ path, body: `（${String(body.length)} 字）` }),
        run: ({ path, body }) => {
          const stored = storedPathOf(path, view);
          if (stored === undefined) return unknownPath(path);
          const next = body.trim();
          if (next.length > FILE_LIMIT) {
            return `文件最多 ${String(FILE_LIMIT)} 字，再精简一些。`;
          }
          draft.files.set(stored, next);
          draft.changed.add(stored);
          return `已重写 ${path}，现在 ${String(next.length)} 字。`;
        },
      }),
    );
  }
  if (replying) {
    tools.push(
      defineTool(draft.steps, {
        name: 'reply',
        description: `${kind === 'checkIn' ? '在这条动态下面回发动态的人一句' : '在这条动态下面回复对方写给你的这句'}。显示在评论区，带「教练」标志，全队都看得到，对方会收到推送。一次醒来只回一句，再调用会换掉上一句。${limitWords('reply')}；超了会告诉你超了多少。前面几个参数是你写之前想的，${privately}，按顺序填完再写 text。`,
        parameters: z.object({
          replying_to_user_id: z
            .string()
            .describe(
              `你这句是回给谁的：他的 user_id。回的是写这句话的人；他不一定是发这条动态的人。${privately}`,
            ),
          their_message: z
            .string()
            .describe(`他这条实际在说什么、问什么，你要接住的是哪件事。${privately}`),
          facts: factsUsed,
          plain_draft: plainDraft,
          anyone_would_say: anyoneWouldSay,
          tone: toneOf,
          text: z
            .string()
            .describe(
              '回的这一句：按 tone 里你的看法来说，是你才会说的话；plain_draft 的意思要在，读的人不用想就懂',
            ),
          mention_user_ids: mentionUserIds,
        }),
        kept: (input) =>
          thoughtLengths(input, [
            'their_message',
            'facts',
            'plain_draft',
            'anyone_would_say',
            'tone',
          ]),
        run: ({ replying_to_user_id: toUserId, facts, text, mention_user_ids: at }) => {
          if (to !== undefined && memberOf(roster, toUserId) !== to) {
            return `replying_to_user_id 不对：这次要回的是${personOf(roster, to)}。把他的事和别人的事分开，重新填。`;
          }
          const wrong = factsProblem(facts, roster);
          if (wrong !== undefined) return wrong;
          const said = mentioning({ line: text.trim(), at, to }, { week, roster });
          if (typeof said === 'string') return said;
          const problem = sayingProblem(said.line, { kind: 'reply', roster });
          if (problem !== undefined) return problem;
          if (kind === 'checkIn') {
            const replaced = draft.reply !== undefined;
            draft.reply = said.line;
            draft.replyMentions = said.mentions;
            return replaced ? '已换成这句。' : '已回复。';
          }
          const replaced = draft.answer !== undefined;
          draft.answer = said.line;
          draft.answerMentions = said.mentions;
          return replaced ? '已换成这句。' : '已回复。';
        },
      }),
    );
  }
  if (kind === 'checkIn') {
    tools.push(
      defineTool(draft.steps, {
        name: 'react',
        description:
          '给这条新发的动态点一个表情，带「教练」标志，全队看得到。一条动态只有你的一个表情，再调用会换掉。别人回复你、@ 你的时候不用点。',
        parameters: z.object({ emoji: CoachEmoji.describe('点的表情') }),
        run: ({ emoji }) => {
          const replaced = draft.reaction !== undefined;
          draft.reaction = emoji;
          return replaced ? `已换成 ${emoji}。` : `已点 ${emoji}。`;
        },
      }),
    );
  }
  if (replying && challenges !== undefined)
    tools.push(dayChallenge(draft.steps, { roster, challenges }));
  if (photos !== undefined && (kind === 'checkIn' || kind === 'comment')) {
    tools.push(lookAtPhotos(draft.steps, photos));
  }
  return tools;
}

/**
 * `day_challenge`: a member's challenge today and how it stands, looked up only when a post or
 * comment is about it (Tracy, 2026-11-14: told it in every task, the coach brought it up under
 * every post).
 */
function dayChallenge(
  steps: WakeStep[],
  {
    roster,
    challenges,
  }: {
    readonly roster: Roster;
    readonly challenges: () => Promise<readonly DayChallengeFacts[]>;
  },
): CoachTool {
  return defineTool(steps, {
    name: 'day_challenge',
    reads: true,
    description:
      '查一个队员今天的挑战：标题和数量、挑战卡上的小字、他接没接、完没完成。挑战每天早上定，在他自己的挑战卡上，他随时看得到，所以平时回复里不用提。有人在这里问到挑战，或者这条动态说的就是在做挑战，才查。今天没给他定就返回没有。',
    parameters: z.object({
      user_id: z.string().describe('查谁：他的 user_id，任务里名字后面括号里的那串'),
    }),
    run: async ({ user_id: userId }) => {
      const id = memberOf(roster, userId);
      if (id === undefined) {
        return `没有 user_id 是「${userId}」的人。小队的人：${peopleOf(roster)}。`;
      }
      let today: readonly DayChallengeFacts[];
      try {
        today = await challenges();
      } catch {
        return '挑战现在查不到，先不提。';
      }
      const found = today.find(({ member }) => member === id);
      if (found === undefined) return `${personOf(roster, id)} 今天没有挑战。`;
      const { challenge } = found;
      return [
        `${personOf(roster, id)} 今天的挑战：${challengeText(challenge)}`,
        ...(challenge.line === undefined ? [] : [`- 挑战卡上的小字：「${challenge.line}」`]),
        `- ${challengeHow(found)}`,
      ].join('\n');
    },
  });
}

/** The longest line a coach writes of what a member asked of the app. */
export const RELAY_LIMIT = 200;

/**
 * Passing on to the team what the member the wake answers asked of the app itself, in their own
 * words there (Tracy, 2026-11-12): saved with the run, then filed like 意见反馈, from them.
 */
function relayFeedback(draft: WakeDraft, heard: boolean): CoachTool {
  return defineTool(draft.steps, {
    name: 'relay_feedback',
    description: `把他对 app 的意见转给做 app 的团队，会附上他在这条动态下面说的原话。他在这里明确说了想让 app 加什么、改什么，或者 app 哪里坏了，才用；聊运动、聊吃的、跟你开玩笑都不算。一次醒来只转一条，再调用会换掉。转了以后，在回他的那句里像朋友一样随口提一句已经转了，用你自己的话。`,
    parameters: z.object({
      kind: z.enum(['problem', 'idea']).describe('app 出了问题是 problem，想要新东西或改进是 idea'),
      text: z
        .string()
        .describe(
          `他想要什么、哪里不对，写清楚让没看过这条动态的人也懂；不写人名和 user_id，不超过 ${String(RELAY_LIMIT)} 字`,
        ),
    }),
    run: ({ kind, text }) => {
      if (!heard) return '他在这里没写字，没有能转的。';
      const line = text.trim();
      if (line === '') return 'text 是空的，写上他想要什么。';
      if (line.length > RELAY_LIMIT) {
        return `太长了：${String(line.length)} 字，最多 ${String(RELAY_LIMIT)} 字。`;
      }
      const replaced = draft.feedback !== undefined;
      draft.feedback = { kind, text: line };
      return replaced ? '已换成这条，会转给团队。' : '会转给团队。';
    },
  });
}

/** The furthest back the coach reads, in weeks before this one, as `squad_week` does. */
const WEEKS_BACK = 4;

/**
 * Looking a member's posts up, and the comments under one on demand: a comment that asks about
 * someone (谁更健康) is answered from what they posted, not guessed. The posts are those the
 * squad's week holds, so only what was shared to this squad, from members with a current AI
 * consent; one only recorded (发布到动态 off) shows what was done, never its words, and has no
 * comments. Each listed post gets a number (动态N) for the run, its post_id, which `post_comments`
 * takes; whose posts is asked by user_id.
 */
function postTools(
  steps: WakeStep[],
  {
    roster,
    weekAgo,
    commentsOf,
    numbers,
  }: {
    readonly roster: Roster;
    readonly weekAgo: (weeksAgo: number) => Promise<SquadWeek>;
    readonly commentsOf: (checkIn: WeekCheckIn) => Promise<readonly string[]>;
    readonly numbers: PostNumbers;
  },
): CoachTool[] {
  return [
    memberPostsTool(steps, { roster, weekAgo, numbers }),
    postCommentsTool(steps, { numbers, commentsOf }),
  ];
}

/**
 * The challenge run's tools: `set_challenge`, and `post_comments` over the posts its task
 * numbered.
 */
export function challengeTools(
  draft: WakeDraft,
  {
    names,
    noteTo,
    numbered,
    commentsOf,
  }: {
    readonly names: Roster;
    readonly noteTo: readonly string[];
    readonly numbered: ReadonlyMap<string, WeekCheckIn>;
    readonly commentsOf: (checkIn: WeekCheckIn) => Promise<readonly string[]>;
  },
): CoachTool[] {
  return [
    challengeTool(draft, { roster: names, noteTo }),
    postCommentsTool(draft.steps, { numbers: PostNumbers.numbered(numbered), commentsOf }),
  ];
}

/** `member_posts`: a member's posts, each numbered (动态N) for `post_comments`. */
function memberPostsTool(
  steps: WakeStep[],
  {
    roster,
    weekAgo,
    numbers,
  }: {
    readonly roster: Roster;
    readonly weekAgo: (weeksAgo: number) => Promise<SquadWeek>;
    readonly numbers: PostNumbers;
  },
): CoachTool {
  const numberOf = (checkIn: WeekCheckIn): string => numbers.of(checkIn);
  return defineTool(steps, {
    name: 'member_posts',
    reads: true,
    description:
      '读一个队员最近发的动态，新的在前。每条返回：post_id（动态N）、哪天、是什么、写了什么、打分、和谁一起练、几张照片、几条评论。评论里有人问到某个人、要拿人比较，或者你想知道一个人最近怎么样，先用它看，不要猜。评论的内容不在这里，用 post_comments 按 post_id 看。',
    parameters: z.object({
      user_id: z.string().describe('看谁：他的 user_id，任务里名字后面括号里的那串'),
      weeks_back: z
        .number()
        .int()
        .min(0)
        .max(WEEKS_BACK)
        .nullable()
        .describe(`往前多看几周：0 只看这周，null 是这周和上周，最多 ${String(WEEKS_BACK)}`),
    }),
    run: async ({ user_id: userId, weeks_back: weeksBack }) => {
      const id = memberOf(roster, userId);
      if (id === undefined) {
        return `没有 user_id 是「${userId}」的人。小队的人：${peopleOf(roster)}。`;
      }
      const weeks = weeksBack ?? 1;
      const member = personOf(roster, id);
      const read = await Promise.all(
        Array.from({ length: weeks + 1 }, (_, weeksAgo) => weekAgo(weeksAgo)),
      );
      const posts = read
        .flatMap(({ checkIns }) => checkIns)
        .filter((each) => each.member === id)
        .toSorted((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
      if (posts.length === 0) return `${member} 这段时间没有能看的动态。`;
      return [
        `# ${member} 的动态（新的在前）`,
        ...posts.map((post) => {
          const block = checkInBlock(post, {
            roster,
            heading: `## ${numberOf(post)} · `,
            comments: false,
          });
          return post.comments.length === 0
            ? block
            : `${block}\n- 评论：${String(post.comments.length)} 条（用 post_comments 看）`;
        }),
      ].join('\n\n');
    },
  });
}

/** `post_comments`: the comment section under a post by its number. */
function postCommentsTool(
  steps: WakeStep[],
  {
    numbers,
    commentsOf,
  }: {
    readonly numbers: PostNumbers;
    readonly commentsOf: (checkIn: WeekCheckIn) => Promise<readonly string[]>;
  },
): CoachTool {
  return defineTool(steps, {
    name: 'post_comments',
    reads: true,
    description:
      '读一条动态下面的评论区。按先后顺序返回每一句：谁说的（名字和 user_id）、回复谁、说了什么；你自己说过的也在里面。要接着一段聊过的话说、或者想知道某条动态下面聊了什么时用。只有任务里或 member_posts 里出现过的 post_id 能查。',
    parameters: z.object({
      post_id: z.string().describe('哪条动态：它的 post_id，写成「动态N」，如 动态12'),
    }),
    run: async ({ post_id: post }) => {
      const checkIn = numbers.find(post);
      if (checkIn === undefined) {
        return numbers.size === 0
          ? `没有 ${post}；先找到那条动态的编号。`
          : `没有 ${post}；能看的是：${numbers.numbers().join('、')}。`;
      }
      if (checkIn.unposted === true) return `${post} 只记录，没发动态，没有评论。`;
      let said: readonly string[];
      try {
        said = await commentsOf(checkIn);
      } catch {
        return '评论现在查不到，先不提。';
      }
      return said.length === 0
        ? `${post} 下面还没有评论。`
        : `${post} 的评论区：\n${said.join('\n')}`;
    },
  });
}

/**
 * Looks at the photos of the check-in this wake is about, on demand (at low detail each costs
 * about as much as a short comment). A check-in's reply needs it only when the post is about
 * what its photos show; a reply to the coach about the post (what's in it, what they ate) needs
 * it every time, since the words alone don't say what the photos show. The step keeps how many
 * it looked at, never the pictures.
 */
function lookAtPhotos(steps: WakeStep[], photos: () => Promise<readonly string[]>): CoachTool {
  const name = 'look_at_photos';
  return {
    name,
    description:
      '看这条动态的照片，返回每一张图，第一张是封面。照片里有什么只有看了才知道：这条动态说的就是照片里的东西（吃了什么、在哪、练了什么），或者有人问照片里的事，就先看再说。一次醒来只能看一次。',
    parameters: z.object({}),
    run: async (): Promise<ToolAnswer> => {
      const looked = steps.some(({ tool }) => tool === name);
      if (looked) {
        steps.push({ tool: name, input: {}, output: '已经看过了。' });
        return '照片你已经看过了，不用再看。';
      }
      let urls: readonly string[];
      try {
        urls = await photos();
      } catch {
        steps.push({ tool: name, input: {}, output: '照片打不开。' });
        return '照片现在打不开，就当没看见，照常回。';
      }
      if (urls.length === 0) {
        steps.push({ tool: name, input: {}, output: '没有照片。' });
        return '这条打卡没有照片。';
      }
      steps.push({ tool: name, input: {}, output: `（${String(urls.length)} 张照片）` });
      return { text: `这条打卡的 ${String(urls.length)} 张照片，第一张是封面：`, images: urls };
    },
  };
}

/**
 * Gives a member a piece from the gift pool, with a line only they see: at most one a member a
 * week (Tracy, 2026-11-08), so only to those the task lists, and never a piece they have. Given
 * once the run's other changes are saved.
 */
function giveGift(
  draft: WakeDraft,
  { roster, gifting }: { readonly roster: Roster; readonly gifting: GiftOptions },
): CoachTool {
  const open = [...gifting.open.keys()];
  return defineTool(draft.steps, {
    name: 'give_gift',
    description: `送一个队员一件衣服，配一句话，只有他自己看得到。能送谁、有哪些衣服，都在任务的礼物清单里。只在真有理由的时候送：理由是他一段时间的样子，练了一次不算；大多数时候谁都不送。每人一周最多一件，一次醒来一人最多一件，再调用会换掉。line ${limitWords('gift')}。`,
    parameters: z.object({
      user_id: z.string().describe('送给谁：他的 user_id'),
      piece_id: z.string().describe('送哪件：礼物清单里那件的 id'),
      line: z.string().describe('送的时候对他说的一句'),
    }),
    kept: ({ user_id: userId, piece_id: piece, line }) => ({
      user_id: userId,
      piece_id: piece,
      line: `（${String(line.length)} 字）`,
    }),
    run: ({ user_id: userId, piece_id: piece, line }) => {
      const id = memberOf(roster, userId);
      const owned = id === undefined ? undefined : gifting.open.get(id);
      if (id === undefined || owned === undefined) {
        return `user_id「${userId}」这周不能收礼物。能收的是：${peopleOf(roster, open)}。`;
      }
      const member = personOf(roster, id);
      const chosen = piece.trim();
      if (!gifting.pool.some(({ id: each }) => each === chosen)) {
        return `没有 ${chosen} 这件；能送的见任务里的礼物清单。`;
      }
      if (owned.includes(chosen)) return `${member} 已经有 ${chosen} 了，换一件。`;
      const said = line.trim();
      const problem = sayingProblem(said, { kind: 'gift', roster });
      if (problem !== undefined) return problem;
      const replaced = draft.gifts.has(id);
      draft.gifts.set(id, { piece: chosen, line: said });
      return replaced ? `已换成 ${chosen}，给 ${member}。` : `${chosen} 送给 ${member} 了。`;
    },
  });
}

/** Whether each of a challenge's words fits its limit in the language it is written in. */
function challengeFits({ title, unit, line }: Challenge): boolean {
  return (
    fitsLine(title, 'challengeTitle') &&
    (unit === undefined || fitsLine(unit, 'challengeUnit')) &&
    (line === undefined || fitsLine(line, 'challengeLine'))
  );
}

/**
 * `set_challenge`: the day's challenge for one member, set on a daily wake by a run of its own
 * before the coach writes its notes (Tracy, 2026-11-12: a stronger model sets them, the coach
 * keeps its own voice in the note). What makes a good one is the settings' `challengeRules`. It
 * first says how the member has been and what they need today (Tracy, 2026-11-14: force a
 * structured thought), which only the wake's steps keep: the member never sees it.
 */
export function challengeTool(
  draft: WakeDraft,
  { roster, noteTo }: { readonly roster: Roster; readonly noteTo: readonly string[] },
): CoachTool {
  return defineTool(draft.steps, {
    name: 'set_challenge',
    description: `给一个队员定今天的挑战：一件今天能做完的事，出现在他的 App 里，他可以接也可以不接。任务里列出的每个人定一个，再调用会换掉上一个。recent 和 needs 是你定之前想的，${privately}，先填它们再定。标题、数量、单位超了字数会告诉你。`,
    parameters: z.object({
      user_id: z.string().describe('给谁：他的 user_id，任务里名字后面括号里的那串'),
      recent: z
        .string()
        .describe(
          `他这几天怎么样：从计划、发的动态、评论、最近的挑战和你对他的了解里看。${privately}`,
        ),
      needs: z.string().describe(`所以今天他最需要什么。${privately}`),
      title: z
        .string()
        .describe(
          `只写动作：动词加做的东西，${limitWords('challengeTitle')}。不写数字、不写「一道」「一份」这类量词，也不写单位；数量只放 amount，单位只放 unit。标题、数量、单位连起来读要通顺`,
        ),
      amount: z
        .number()
        .int()
        .describe(`多少，正整数，不超过 ${String(CHALLENGE_AMOUNT_MAX)}`),
      unit: z.string().describe(`单位，${limitWords('challengeUnit')}`),
      line: z
        .string()
        .describe(
          `标题下面的一句小字，对他说为什么是这件事，用「你」，${limitWords('challengeLine')}`,
        ),
    }),
    run: ({ user_id: userId, title, amount, unit, line }) => {
      const id = memberOf(roster, userId);
      if (id === undefined || !noteTo.includes(id)) {
        return `不能给 user_id「${userId}」定挑战。能定的是：${peopleOf(roster, noteTo)}。`;
      }
      const member = personOf(roster, id);
      const set = Challenge.safeParse({
        title,
        amount,
        unit,
        ...(line.trim() === '' ? {} : { line }),
      });
      if (!set.success || !challengeFits(set.data)) {
        return `挑战不对：title ${limitWords('challengeTitle')}；amount 是 1 到 ${String(CHALLENGE_AMOUNT_MAX)} 的整数；unit ${limitWords('challengeUnit')}；line ${limitWords('challengeLine')}。`;
      }
      // The member reads all three on the card.
      const leaked = userIdIn(roster, [title, unit, line].join('\n'));
      if (leaked !== undefined) {
        return `挑战里写了 user_id「${leaked}」。user_id 只在工具参数里用，给人看的话里只写名字。`;
      }
      const replaced = draft.challenges.has(id);
      draft.challenges.set(id, set.data);
      return `${replaced ? '已换成' : '定好了'}：${member}「${challengeText(set.data)}」。`;
    },
  });
}

/**
 * `note_to`: a note to one member only they read. On a daily wake it is their morning note,
 * delivered on their clock, which may set a day's challenge; on a welcome it reaches them at once
 * and sets none (Tracy, 2026-11-12: 只写欢迎).
 */
function noteTool(
  draft: WakeDraft,
  {
    roster,
    noteTo,
    welcome,
  }: {
    readonly roster: Roster;
    readonly noteTo: readonly string[];
    readonly welcome: boolean;
  },
): CoachTool {
  const write = ({
    user_id: userId,
    facts = [],
    text,
  }: {
    readonly user_id: string;
    readonly facts?: readonly { readonly about_user_id: string | null }[];
    readonly text: string;
  }): string => {
    const id = memberOf(roster, userId);
    if (id === undefined || !noteTo.includes(id)) {
      return `不能给 user_id「${userId}」写便条。能写的是：${peopleOf(roster, noteTo)}。`;
    }
    const wrong = factsProblem(facts, roster);
    if (wrong !== undefined) return wrong;
    const member = personOf(roster, id);
    const line = text.trim();
    const problem = sayingProblem(line, { kind: 'note', roster });
    if (problem !== undefined) return problem;
    // The day's challenge set for them before, if any, goes on the note; a welcome sets none.
    const set = welcome ? undefined : draft.challenges.get(id);
    const replaced = draft.memberNotes.has(id);
    draft.memberNotes.set(id, { text: line, ...(set === undefined ? {} : { challenge: set }) });
    const done = replaced ? `已换成这张，给 ${member}` : `便条写好了，给 ${member}`;
    return set === undefined ? `${done}。` : `${done}，下面附着挑战「${challengeText(set)}」。`;
  };
  const userId = z.string().describe('写给谁：他的 user_id，任务里名字后面括号里的那串');
  // Kept by length: it is about the member, and stays in its own table.
  const kept = (input: Readonly<Record<string, unknown>>): unknown =>
    thoughtLengths(input, ['topic', 'facts', 'plain_draft', 'anyone_would_say', 'tone', 'text']);
  if (welcome) {
    return defineTool(draft.steps, {
      name: 'note_to',
      description: `给刚加入小队的人写一张便条。只有他自己看得到，现在就送到他手机上。一人一张，再调用会换掉上一张。${limitWords('note')}，对他说话用「你」；超了会告诉你超了多少。`,
      parameters: z.object({ user_id: userId, text: z.string().describe('便条上的话') }),
      kept,
      run: write,
    });
  }
  return defineTool(draft.steps, {
    name: 'note_to',
    description: `给一个队员写今天的便条。只有他自己看得到，早上（他那里的时间）跟他今天的挑战卡一起送到他手机上。任务里列出的每个人一张，再调用会换掉上一张。${limitWords('note')}，对他说话用「你」；超了会告诉你超了多少。中间几个参数是你写之前想的，${privately}，按顺序填完再写 text。`,
    parameters: z.object({
      user_id: userId,
      topic: z.string().describe(`今天对他说哪一件事，为什么是这件。${privately}`),
      facts: factsUsed,
      plain_draft: plainDraft,
      anyone_would_say: anyoneWouldSay,
      tone: toneOf,
      text: z
        .string()
        .describe(
          '便条上的这一句：按 tone 里你的看法来说，是你才会说的话；plain_draft 的意思要在，读的人不用想就懂',
        ),
    }),
    kept,
    run: write,
  });
}
