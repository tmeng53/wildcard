import type { StoredPath } from '../domain/memory.js';
import type { SquadId } from '../domain/settings.js';
import type { CoachMemoryStore } from '../ports.js';

/** A squad's coach memory as the admins keep it: read whole, rewritten a file at a time. */
export interface CoachMemoryAdmin {
  /**
   * Replaces one of the squad's files with `body` (empty clears it), as stored: members as
   * `{队员:<member id>}`. Every version is kept. Answers the squad's files now.
   */
  rewrite(input: {
    readonly squad: SquadId;
    readonly path: StoredPath;
    readonly body: string;
  }): Promise<{
    readonly version: 1;
    readonly files: readonly { readonly path: StoredPath; readonly body: string }[];
  }>;
}

export function createCoachMemory({
  memory,
}: {
  readonly memory: CoachMemoryStore;
}): CoachMemoryAdmin {
  return {
    async rewrite({ squad, path, body }) {
      const files = await memory.files(squad);
      const next = body.trim();
      if (next !== (files.get(path) ?? ''))
        await memory.save({ squad, files: [{ path, body: next }] });
      const now = new Map(files).set(path, next);
      return {
        version: 1,
        files: [...now].map(([each, text]) => ({ path: each, body: text })),
      };
    },
  };
}
