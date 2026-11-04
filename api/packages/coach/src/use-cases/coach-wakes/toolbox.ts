import { z } from 'zod';

import { editBody, storedPathOf, type StoredPath } from '../../domain/memory.js';
import { NOTE_LIMIT } from '../../domain/prompt.js';
import { CoachEmoji, lineProblem, REPLY_LIMIT } from '../../domain/reply.js';
import { weekText, type SquadWeek } from '../../domain/squad-week.js';
import type { WakeReason, WakeStep } from '../../domain/wake.js';
import type { CoachTool } from '../../ports.js';

/** What a wake's tools change, kept in memory until the run ends and saved together then. */
export interface WakeDraft {
  /** The squad's files, by stored path, as the run left them. */
  readonly files: Map<StoredPath, string>;
  /** The files the run changed. */
  readonly changed: Set<StoredPath>;
  /** The 战术板 line the run posted, on a daily wake. */
  note: string | undefined;
  /** What the run said to the check-in, on its wake. */
  reply: string | undefined;
  /** The emoji the run reacted to the check-in with, on its wake. */
  reaction: CoachEmoji | undefined;
  /** What the run answered a member's reply to it, on that reply's wake. */
  answer: string | undefined;
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
    run(input: z.infer<Shape>): string;
  },
): CoachTool {
  return {
    name: tool.name,
    description: tool.description,
    parameters: tool.parameters,
    run: (input) => {
      const parsed = tool.parameters.safeParse(input);
      const output = parsed.success
        ? tool.run(parsed.data)
        : `参数不对：${z.prettifyError(parsed.error)}`;
      steps.push({
        tool: tool.name,
        input: parsed.success && tool.kept !== undefined ? tool.kept(parsed.data) : input,
        output: tool.reads === true && parsed.success ? `（${String(output.length)} 字）` : output,
      });
      return Promise.resolve(output);
    },
  };
}

/**
 * The tools a coach has on a wake: reading the squad's week and its files, editing the files,
 * on a daily wake posting the 战术板 line, on a check-in's wake replying and reacting to it, and
 * on a reply's wake answering it. Nothing is saved until the run ends.
 */
export function toolbox({
  week,
  roster,
  draft,
  kind,
}: {
  readonly week: SquadWeek;
  readonly roster: ReadonlyMap<string, string>;
  readonly draft: WakeDraft;
  readonly kind: WakeReason['kind'];
}): CoachTool[] {
  const unknownPath = (path: string) => `没有 ${path} 这个文件；能用的文件见任务里的列表。`;
  const tools = [
    defineTool(draft.steps, {
      name: 'squad_week',
      reads: true,
      description: '这周小队的情况：队员和外号，每个人的打卡、表情和评论。',
      parameters: z.object({}),
      run: () => weekText(week),
    }),
    defineTool(draft.steps, {
      name: 'read_file',
      reads: true,
      description: '读一个文件的全部内容。',
      parameters: z.object({
        path: z.string().describe('文件路径，如 memory.md、people/队员1.md'),
      }),
      run: ({ path }) => {
        const stored = storedPathOf(path, roster);
        if (stored === undefined) return unknownPath(path);
        const body = draft.files.get(stored) ?? '';
        return body === '' ? '（空文件）' : body;
      },
    }),
    defineTool(draft.steps, {
      name: 'edit_file',
      description:
        '改一个文件：把 find 的原文换成 replace。find 必须在文件里正好出现一次；find 为空时，把 replace 加到文件末尾。删掉一段就让 replace 为空。',
      parameters: z.object({
        path: z.string().describe('文件路径，如 memory.md、people/队员1.md'),
        find: z.string().describe('要换掉的原文，照抄；为空就是加到末尾'),
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
    );
  }
  if (kind === 'checkIn') {
    tools.push(
      defineTool(draft.steps, {
        name: 'reply',
        description: `回这条打卡一句：显示在这条动态的评论里，带「教练」标志，全队都看得到。一条打卡只回一句，再回会换掉这句。不超过 ${String(REPLY_LIMIT)} 字。`,
        parameters: z.object({ text: z.string().describe('回的这一句') }),
        run: ({ text }) => {
          const line = text.trim();
          const problem = lineProblem(line, REPLY_LIMIT);
          if (problem !== undefined) return problem;
          const replaced = draft.reply !== undefined;
          draft.reply = line;
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
        parameters: z.object({ text: z.string().describe('回的这一句') }),
        run: ({ text }) => {
          const line = text.trim();
          const problem = lineProblem(line, REPLY_LIMIT);
          if (problem !== undefined) return problem;
          const replaced = draft.answer !== undefined;
          draft.answer = line;
          return replaced ? '已换成这句。' : '已回复。';
        },
      }),
    );
  }
  return tools;
}
