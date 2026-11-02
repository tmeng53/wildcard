import { z } from 'zod';

import { editBody, storedPathOf, type StoredPath } from '../../domain/memory.js';
import { NOTE_LIMIT } from '../../domain/prompt.js';
import { weekText, type SquadWeek } from '../../domain/squad-week.js';
import type { CoachTool } from '../../ports.js';

/** What a wake's tools change, kept in memory until the run ends and saved together then. */
export interface WakeDraft {
  /** The squad's files, by stored path, as the run left them. */
  readonly files: Map<StoredPath, string>;
  /** The files the run changed. */
  readonly changed: Set<StoredPath>;
  /** The 战术板 line the run posted, on a daily wake. */
  note: string | undefined;
}

/** A tool whose arguments are checked against its own shape before it runs. */
function defineTool<Shape extends z.ZodObject>(tool: {
  readonly name: string;
  readonly description: string;
  readonly parameters: Shape;
  run(input: z.infer<Shape>): string;
}): CoachTool {
  return {
    name: tool.name,
    description: tool.description,
    parameters: tool.parameters,
    run: (input) => {
      const parsed = tool.parameters.safeParse(input);
      return Promise.resolve(
        parsed.success ? tool.run(parsed.data) : `参数不对：${z.prettifyError(parsed.error)}`,
      );
    },
  };
}

/**
 * The tools a coach has on a wake: reading the squad's week and its files, editing the files,
 * and on a daily wake, posting the 战术板 line. Nothing is saved until the run ends.
 */
export function toolbox({
  week,
  roster,
  draft,
  daily,
}: {
  readonly week: SquadWeek;
  readonly roster: ReadonlyMap<string, string>;
  readonly draft: WakeDraft;
  readonly daily: boolean;
}): CoachTool[] {
  const unknownPath = (path: string) => `没有 ${path} 这个文件；能用的文件见任务里的列表。`;
  const tools = [
    defineTool({
      name: 'squad_week',
      description: '这周小队的情况：队员和外号，每个人的打卡、表情和评论。',
      parameters: z.object({}),
      run: () => weekText(week),
    }),
    defineTool({
      name: 'read_file',
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
    defineTool({
      name: 'edit_file',
      description:
        '改一个文件：把 find 的原文换成 replace。find 必须在文件里正好出现一次；find 为空时，把 replace 加到文件末尾。删掉一段就让 replace 为空。',
      parameters: z.object({
        path: z.string().describe('文件路径，如 memory.md、people/队员1.md'),
        find: z.string().describe('要换掉的原文，照抄；为空就是加到末尾'),
        replace: z.string().describe('换成的新内容'),
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
  if (daily) {
    tools.push(
      defineTool({
        name: 'post_note',
        description: `在小队的战术板上写今天的一句，全队都看得到。一天一句，再写会换掉这句。不超过 ${String(NOTE_LIMIT)} 字。`,
        parameters: z.object({ text: z.string().describe('今天的一句') }),
        run: ({ text }) => {
          const line = text.trim();
          if (line === '') return '这句是空的。';
          if (line.length > NOTE_LIMIT)
            return `太长了：${String(line.length)} 字，最多 ${String(NOTE_LIMIT)} 字。`;
          const replaced = draft.note !== undefined;
          draft.note = line;
          return replaced ? '已换成这句。' : '已写上战术板。';
        },
      }),
    );
  }
  return tools;
}
