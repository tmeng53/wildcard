// A squad's memory: the files its coach keeps. Stored by member id (`people/<id>.md`), shown to
// the model by roster name (`people/队员N.md`), so the model never sees an id and a member's
// page follows them when the numbering changes.

/** The longest a file may grow, in characters; the database checks the same. */
export const FILE_LIMIT = 8000;

/** The files every squad has, empty until the coach writes them. */
const SQUAD_FILES = ['squad.md', 'memory.md'] as const;

/** A file's path as stored: `squad.md`, `memory.md` or `people/<member id>.md`. */
export type StoredPath = string;

/** Every path the model may read or edit for this roster, shown as it sees them. */
export function shownPaths(roster: ReadonlyMap<string, string>): string[] {
  return [...SQUAD_FILES, ...[...roster.values()].map((name) => `people/${name}.md`)];
}

/** The stored path for a path the model named, or `undefined` for one it may not use. */
export function storedPathOf(
  shown: string,
  roster: ReadonlyMap<string, string>,
): StoredPath | undefined {
  if (SQUAD_FILES.some((path) => path === shown)) return shown;
  for (const [member, name] of roster) {
    if (shown === `people/${name}.md`) return `people/${member}.md`;
  }
  return undefined;
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
    if (at === -1) return { ok: false, why: '没找到 find 的原文。先 read_file 看看现在的内容。' };
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
