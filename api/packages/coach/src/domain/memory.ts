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
    if (at === -1) return { ok: false, why: '没找到 find 的原文。照抄任务里「你的记性」的原文。' };
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
