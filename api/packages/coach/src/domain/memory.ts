import { z } from 'zod';

import type { SquadWeek } from './squad-week.js';

// A squad's memory: the files its coach keeps. Stored by member id (`people/<id>.md`), shown to
// the model by roster name (`people/队员N.md`), so the model never sees an id and a member's
// page follows them when the numbering changes. Each coach also keeps a page of its own in the
// squad (`coaches/<coach id>.md`, shown to it as `me.md`), which only that coach reads: a coach
// who comes back finds its page again, and a new one starts its own (Tracy, 2026-11-09).

/** The longest a file may grow, in characters, as the model sees it. */
export const FILE_LIMIT = 8000;

/** The files every squad has, empty until the coach writes them. */
const SQUAD_FILES = ['squad.md', 'memory.md'] as const;

/** The coach's own page as the model sees it. */
const OWN_PAGE = 'me.md';

/**
 * A file's path as stored: `squad.md`, `memory.md`, `people/<member id>.md` or
 * `coaches/<coach id>.md`.
 */
export type StoredPath = string;

/** A stored path as an admin names it. */
export const CoachFilePath = z
  .string()
  .regex(
    /^(squad\.md|memory\.md|people\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.md|coaches\/[a-z][a-z0-9-]{1,39}\.md)$/,
  );

/** Whose eyes the files are shown to: the squad's roster names and the coach reading them. */
export interface MemoryView {
  /** Each member's roster name (`队员N`), by member id. */
  readonly roster: ReadonlyMap<string, string>;
  /** The coach reading the files, by id: it sees its own page and no other coach's. */
  readonly coach: string;
}

/** The stored path of a coach's own page in a squad. */
export function coachPagePath(coach: string): StoredPath {
  return `coaches/${coach}.md`;
}

/**
 * What a file is for, as the model reads it beside the file (Tracy, 2026-11-12: say what things
 * are). `me.md` is the coach's own: how members like to talk with it and what they make of it.
 */
export function fileRole(shown: string): string {
  if (shown === 'squad.md') return '这个小队';
  if (shown === 'memory.md') return '你和大家之间的事';
  if (shown === OWN_PAGE) {
    return '你自己：大家喜欢怎么跟你打交道、怎么看你这个教练，只有你读得到';
  }
  const person = /^people\/(.+)\.md$/.exec(shown)?.[1];
  return person === undefined ? '' : `${person}这个人`;
}

/** Every path the model may read or edit, shown as it sees them. */
export function shownPaths({ roster }: MemoryView): string[] {
  return [...SQUAD_FILES, OWN_PAGE, ...[...roster.values()].map((name) => `people/${name}.md`)];
}

/** The stored path for a path the model named, or `undefined` for one it may not use. */
export function storedPathOf(shown: string, { roster, coach }: MemoryView): StoredPath | undefined {
  if (SQUAD_FILES.some((path) => path === shown)) return shown;
  if (shown === OWN_PAGE) return coachPagePath(coach);
  for (const [member, name] of roster) {
    if (shown === `people/${name}.md`) return `people/${member}.md`;
  }
  return undefined;
}

/**
 * The path the model sees for a stored one, or `undefined` for a file it may not read: another
 * coach's page, or the page of someone no longer on the roster.
 */
export function shownPathOf(stored: StoredPath, { roster, coach }: MemoryView): string | undefined {
  if (SQUAD_FILES.some((path) => path === stored)) return stored;
  if (stored === coachPagePath(coach)) return OWN_PAGE;
  const member = memberOfPath(stored);
  const name = member === undefined ? undefined : roster.get(member);
  return name === undefined ? undefined : `people/${name}.md`;
}

// In a file's text, the model names members by roster name too, but the numbering changes when
// someone leaves, so a body is stored with each name as the member's id (`{队员:<id>}`) and shown
// with each id as the member's name now. A member who left is shown as 一位已离队的队员.

/** A body as stored: each roster name in it as its member's id. */
export function storedBody(shown: string, roster: ReadonlyMap<string, string>): string {
  const members = new Map([...roster].map(([member, name]) => [name, member]));
  return shown.replace(/队员\d+/g, (name) => {
    const member = members.get(name);
    return member === undefined ? name : `{队员:${member}}`;
  });
}

/** A body as the model reads it: each member's id in it as their roster name now. */
export function shownBody(stored: string, roster: ReadonlyMap<string, string>): string {
  return stored.replace(
    /\{队员:([0-9a-f-]{36})\}/g,
    (_token, member: string) => roster.get(member) ?? '一位已离队的队员',
  );
}

/** The member a stored `people/` page is about. */
export function memberOfPath(path: StoredPath): string | undefined {
  return /^people\/(.+)\.md$/.exec(path)?.[1];
}

/** What an edit did: the new body, or why it couldn't be made, for the model to fix. */
export type Edited =
  { readonly ok: true; readonly body: string } | { readonly ok: false; readonly why: string };

/**
 * Edits a file's body: replaces the one place `find` occurs with `replace`, or with an empty
 * `find`, adds `replace` at the end on a line of its own. Refuses when `find` occurs nowhere or
 * more than once, or the file would grow past `FILE_LIMIT`.
 */
export function editBody(
  body: string,
  { find, replace }: { readonly find: string; readonly replace: string },
): Edited {
  let next: string;
  if (find === '') {
    next = body === '' ? replace : `${body.replace(/\n*$/, '')}\n${replace}`;
  } else {
    const at = body.indexOf(find);
    if (at === -1) return { ok: false, why: '没找到 find 的原文。先用 recall 查出原文，再照抄。' };
    if (body.slice(at + 1).includes(find)) {
      return { ok: false, why: 'find 的原文出现了不止一次，多带几个字让它只出现一次。' };
    }
    next = body.slice(0, at) + replace + body.slice(at + find.length);
  }
  if (next.length > FILE_LIMIT) {
    return { ok: false, why: `文件最多 ${String(FILE_LIMIT)} 字，先删掉不再需要的内容。` };
  }
  return { ok: true, body: next };
}

/**
 * The first `squad.md` of a squad whose coach hasn't written one: its name, for the coach to build
 * on. Who is in it and their nicknames aren't copied in: every task says who is who as they are
 * now, and a copy here went stale and named people wrongly (Tracy, 2026-11-12).
 */
export function squadSeed(week: Pick<SquadWeek, 'name'>): string {
  return ['# 小队', ...(week.name === undefined ? [] : [`队名：${week.name}`])].join('\n');
}

/** The most `recall` answers with, in characters. */
export const RECALL_LIMIT = 2000;

/** The text's first `end` UTF-16 units, one fewer if the cut would split a surrogate pair. */
export function sliceWhole(text: string, end: number): string {
  const code = text.charCodeAt(end - 1);
  const splits = end < text.length && code >= 0xd800 && code <= 0xdbff;
  return text.slice(0, splits ? end - 1 : end);
}

/**
 * The lines of the coach's files that match what it looks for, in each file's order (the night
 * keeps what matters most at the top): every line of the files asked for, or only those holding
 * any of the query's words. Each file is named by the path the model sees.
 */
export function recallLines(
  files: ReadonlyMap<string, string>,
  { path, query }: { readonly path?: string; readonly query?: string },
): string {
  if (path !== undefined && !files.has(path)) {
    return `没有 ${path} 这个文件；能查的是：${[...files.keys()].join('，')}。`;
  }
  const terms = (query ?? '')
    .toLowerCase()
    .split(/[\s，,、。；;：:！!？?]+/)
    .filter((term) => term !== '');
  const found: string[] = [];
  for (const [shown, body] of files) {
    if (path !== undefined && shown !== path) continue;
    const lines = body
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line !== '' && !line.startsWith('#'))
      .filter(
        (line) => terms.length === 0 || terms.some((term) => line.toLowerCase().includes(term)),
      );
    found.push(...lines.map((line) => `【${shown}】${line}`));
  }
  if (found.length === 0) {
    return terms.length === 0
      ? '没查到，这些文件还是空的。查不到的就是不记得，别说你记得。'
      : '没查到。可以换更短的词，或者不填 query 看整个文件。还是没有，就是不记得，别说你记得。';
  }
  const shown: string[] = [];
  let length = 0;
  for (const line of found) {
    // A line longer than the whole answer is cut, so it is never left out for good.
    if (shown.length === 0 && line.length > RECALL_LIMIT) {
      shown.push(`${sliceWhole(line, RECALL_LIMIT - 1)}…`);
      length = RECALL_LIMIT;
      continue;
    }
    if (length + line.length + 1 > RECALL_LIMIT) break;
    shown.push(line);
    length += line.length + 1;
  }
  const left = found.length - shown.length;
  return [
    ...shown,
    ...(left === 0 ? [] : [`（还有 ${String(left)} 行没列出，换个更具体的词再查）`]),
  ].join('\n');
}
