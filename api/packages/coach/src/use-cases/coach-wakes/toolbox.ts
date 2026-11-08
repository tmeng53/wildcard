import { z } from 'zod';

import { editBody, FILE_LIMIT, storedPathOf, type StoredPath } from '../../domain/memory.js';
import { NOTE_LIMIT } from '../../domain/prompt.js';
import { CoachEmoji, lineProblem, REPLY_LIMIT } from '../../domain/reply.js';
import { weekText, type SquadWeek } from '../../domain/squad-week.js';
import type { WakeReason, WakeStep } from '../../domain/wake.js';
import type { CoachMemes, CoachTool, ToolAnswer } from '../../ports.js';

/** What a wake's tools change, kept in memory until the run ends and saved together then. */
export interface WakeDraft {
  /** The squad's files, by stored path, as the run left them. */
  readonly files: Map<StoredPath, string>;
  /** The files the run changed. */
  readonly changed: Set<StoredPath>;
  /** The 战术板 line the run posted, on a daily wake. */
  note: string | undefined;
  /** The morning note (便条) the run wrote to each member, by member id, on a daily wake. */
  readonly memberNotes: Map<string, string>;
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
        input: parsed.success && tool.kept !== undefined ? tool.kept(parsed.data) : input,
        output: tool.reads === true && parsed.success ? `（${String(output.length)} 字）` : output,
      });
      return output;
    },
  };
}

/**
 * A line that @s teammates (队员N, as the model names them): each gets 「@昵称」 at the front
 * unless the line already has it, and their ids, or why it can't be said.
 */
export function mentioning(
  { line, at }: { readonly line: string; readonly at: readonly string[] },
  {
    week,
    roster,
  }: { readonly week: Pick<SquadWeek, 'members'>; readonly roster: ReadonlyMap<string, string> },
): { readonly line: string; readonly mentions: readonly string[] } | string {
  const mentions: string[] = [];
  const prefix: string[] = [];
  for (const name of new Set(at.map((each) => each.trim()))) {
    const member = [...roster].find(([, shown]) => shown === name)?.[0];
    const nickname = week.members.find((each) => each.member === member)?.nickname;
    if (member === undefined || nickname === undefined) {
      const known = week.members.flatMap((each) =>
        each.nickname === undefined ? [] : [roster.get(each.member) ?? ''],
      );
      return known.length === 0
        ? `不能 @ ${name}；现在没有能 @ 的队友。`
        : `不能 @ ${name}；能 @ 的是：${known.join('、')}。`;
    }
    mentions.push(member);
    if (!line.includes(`@${nickname}`)) prefix.push(`@${nickname} `);
  }
  return { line: prefix.join('') + line, mentions };
}

/** The `at` parameter of a line the coach says under a check-in. */
const atParameter = z
  .array(z.string())
  .max(3)
  .optional()
  .describe(
    '要 @ 的队友，填 队员N（不只是发帖的人，评论区里谁都能 @）；对方会收到推送，句首自动加上「@昵称」',
  );

/**
 * The tools a coach has on a wake: reading the squad's week, remembering and tidying its files,
 * on a daily wake posting the 战术板 line, on a check-in's wake replying and reacting to it, and
 * on a reply's wake answering it. Nothing is saved until the run ends.
 */
export function toolbox({
  week,
  roster,
  draft,
  kind,
  photos,
  facts,
  pastWeek,
  memes,
  noteTo = [],
}: {
  readonly week: SquadWeek;
  readonly roster: ReadonlyMap<string, string>;
  readonly draft: WakeDraft;
  readonly kind: WakeReason['kind'];
  /** The URLs of the photos of the check-in this wake is about, when it has any to look at. */
  readonly photos?: () => Promise<readonly string[]>;
  /** The members' stats and this week's plans, as the model reads them. */
  readonly facts?: () => Promise<string>;
  /** A week before this one, as the model reads it. */
  readonly pastWeek?: (weeksAgo: number) => Promise<string>;
  /** The memes in use now, for humour. */
  readonly memes?: CoachMemes;
  /** On a daily wake, the members the coach may write a morning note to, by id. */
  readonly noteTo?: readonly string[];
}): CoachTool[] {
  const unknownPath = (path: string) => `没有 ${path} 这个文件；能用的文件见任务里的列表。`;
  const tools = [
    defineTool(draft.steps, {
      name: 'squad_week',
      reads: true,
      description:
        '小队一周的情况：队员和外号，每个人的打卡、表情和评论。默认这周，weeks_ago 填 1 到 4 看前几周。',
      parameters: z.object({
        weeks_ago: z.number().int().min(0).max(4).optional().describe('看几周前，0 或不填是这周'),
      }),
      run: async ({ weeks_ago: weeksAgo = 0 }) =>
        weeksAgo === 0 || pastWeek === undefined ? weekText(week) : await pastWeek(weeksAgo),
    }),
    defineTool(draft.steps, {
      name: 'remember',
      description:
        '把一件事记进你的记性，一次一件，一句话。值得记的是过很久还成立、会改变你以后怎么跟他们说话的事。短期的、琐碎的、记性里已经有的，不记。',
      parameters: z.object({
        path: z
          .string()
          .describe(
            '记到哪：people/队员N.md 记这个人，squad.md 记小队，memory.md 记你和大家之间的事',
          ),
        fact: z.string().describe('要记的这件事，一句话，用队员N称呼人'),
      }),
      kept: ({ path, fact }) => ({ path, fact: `（${String(fact.length)} 字）` }),
      run: ({ path, fact }) => {
        const stored = storedPathOf(path, roster);
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
        '改记性，让它保持准确、不重复：把一个文件里 find 的原文换成 replace，replace 为空就是删。find 照抄任务里「你的记性」的原文，必须正好出现一次。',
      parameters: z.object({
        path: z.string().describe('文件路径，如 memory.md、people/队员1.md'),
        find: z.string().describe('要换掉的原文，照抄'),
        replace: z.string().describe('换成的新内容'),
      }),
      // A file's text may be a member's words, kept in the file only as long as the file has it.
      kept: ({ path, find, replace }) => ({
        path,
        find: `（${String(find.length)} 字）`,
        replace: `（${String(replace.length)} 字）`,
      }),
      run: ({ path, find, replace }) => {
        const stored = storedPathOf(path, roster);
        if (stored === undefined) return unknownPath(path);
        const edited = editBody(draft.files.get(stored) ?? '', { find, replace });
        if (!edited.ok) return edited.why;
        draft.files.set(stored, edited.body);
        draft.changed.add(stored);
        return `已改好，${path} 现在 ${String(edited.body.length)} 字。`;
      },
    }),
  ];
  if (facts !== undefined) {
    tools.push(
      defineTool(draft.steps, {
        name: 'member_stats',
        reads: true,
        description:
          '每个队员的数据：从加入到现在一共练了几天，健康餐、放纵餐、请假条各几次，最常练的运动，拿过几个周奖，还有这周的出赛表和饮食小目标。',
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
          '梗库：现在大家在玩的梗，每个的意思和来历。想找幽默灵感时看，合适才用，不硬套。',
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
  if (kind === 'daily') {
    tools.push(
      defineTool(draft.steps, {
        name: 'post_note',
        description: `在小队的战术板上写今天的一句，全队都看得到。一天一句，再写会换掉这句。不超过 ${String(NOTE_LIMIT)} 字。`,
        parameters: z.object({ text: z.string().describe('今天的一句') }),
        run: ({ text }) => {
          const line = text.trim();
          const problem = lineProblem(line, NOTE_LIMIT);
          if (problem !== undefined) return problem;
          const replaced = draft.note !== undefined;
          draft.note = line;
          return replaced ? '已换成这句。' : '已写上战术板。';
        },
      }),
      defineTool(draft.steps, {
        name: 'note_to',
        description: `给一个队员写今天的便条：只有这个人自己看得到，早上（他那里的时间）送到他手机上。一人一张，再写会换掉。不超过 ${String(NOTE_LIMIT)} 字，对他说话用「你」。`,
        parameters: z.object({
          member: z.string().describe('写给谁：队员N'),
          text: z.string().describe('便条上的这一句'),
        }),
        // Kept by length: it is about the member, and stays in its own table.
        kept: ({ member, text }) => ({ member, text: `（${String(text.length)} 字）` }),
        run: ({ member, text }) => {
          const id = [...roster].find(([, name]) => name === member.trim())?.[0];
          if (id === undefined || !noteTo.includes(id)) {
            return `不能给 ${member} 写便条；能写的是：${noteTo.map((each) => roster.get(each) ?? '').join('、')}。`;
          }
          const line = text.trim();
          const problem = lineProblem(line, NOTE_LIMIT);
          if (problem !== undefined) return problem;
          const replaced = draft.memberNotes.has(id);
          draft.memberNotes.set(id, line);
          return replaced ? `已换成这张，给 ${member}。` : `便条写好了，给 ${member}。`;
        },
      }),
    );
  }
  if (kind === 'dream') {
    tools.push(
      defineTool(draft.steps, {
        name: 'rewrite_file',
        description: `把记性里的一个文件整个换成新写的内容：留下的照写，删掉的不写。body 为空就是清空。不超过 ${String(FILE_LIMIT)} 字。`,
        parameters: z.object({
          path: z.string().describe('文件路径，如 memory.md、people/队员1.md'),
          body: z.string().describe('这个文件的全部新内容，用队员N称呼人'),
        }),
        kept: ({ path, body }) => ({ path, body: `（${String(body.length)} 字）` }),
        run: ({ path, body }) => {
          const stored = storedPathOf(path, roster);
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
  if (kind === 'checkIn') {
    tools.push(
      defineTool(draft.steps, {
        name: 'reply',
        description: `回这条打卡一句：显示在这条动态的评论里，带「教练」标志，全队都看得到。一条打卡只回一句，再回会换掉这句。不超过 ${String(REPLY_LIMIT)} 字。`,
        parameters: z.object({ text: z.string().describe('回的这一句'), at: atParameter }),
        run: ({ text, at = [] }) => {
          const said = mentioning({ line: text.trim(), at }, { week, roster });
          if (typeof said === 'string') return said;
          const problem = lineProblem(said.line, REPLY_LIMIT);
          if (problem !== undefined) return problem;
          const replaced = draft.reply !== undefined;
          draft.reply = said.line;
          draft.replyMentions = said.mentions;
          return replaced ? '已换成这句。' : '已回复。';
        },
      }),
      defineTool(draft.steps, {
        name: 'react',
        description: '给这条打卡点一个表情，带「教练」标志。一条打卡只点一个，再点会换掉。',
        parameters: z.object({ emoji: CoachEmoji.describe('点的表情') }),
        run: ({ emoji }) => {
          const replaced = draft.reaction !== undefined;
          draft.reaction = emoji;
          return replaced ? `已换成 ${emoji}。` : `已点 ${emoji}。`;
        },
      }),
    );
  }
  if (kind === 'comment') {
    tools.push(
      defineTool(draft.steps, {
        name: 'answer',
        description: `回复这位队员回你的这句：显示在评论里，是你回复对方，带「教练」标志，全队都看得到，对方会收到推送。只回一句，再回会换掉这句。不超过 ${String(REPLY_LIMIT)} 字。`,
        parameters: z.object({ text: z.string().describe('回的这一句'), at: atParameter }),
        run: ({ text, at = [] }) => {
          const said = mentioning({ line: text.trim(), at }, { week, roster });
          if (typeof said === 'string') return said;
          const problem = lineProblem(said.line, REPLY_LIMIT);
          if (problem !== undefined) return problem;
          const replaced = draft.answer !== undefined;
          draft.answer = said.line;
          draft.answerMentions = said.mentions;
          return replaced ? '已换成这句。' : '已回复。';
        },
      }),
    );
  }
  if (photos !== undefined && (kind === 'checkIn' || kind === 'comment')) {
    tools.push(lookAtPhotos(draft.steps, photos));
  }
  return tools;
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
      '看这条打卡的照片。照片里有什么，只有看了才知道。看照片比读文字贵很多，一次醒来最多看一次。',
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
