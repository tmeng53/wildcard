import { sql, type Kysely } from 'kysely';

import { ArtPath, type ArtFile } from '../domain/art.js';
import type { ArtStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads, as generated from the migrations. */
export type ArtTables = DB;

/** Which file stands at each path, on Postgres (`art_files`, its own log). */
export function createPostgresArtStore(db: Kysely<ArtTables>): ArtStore {
  return {
    async manifest() {
      // One read, so the generation is the newest of the very rows listed (the newest row of
      // all is the newest of its path).
      const latest = await db
        .selectFrom('art_files')
        .distinctOn('path')
        .select(['id', 'path', 'sha256', 'size', 'rig_version'])
        .orderBy('path')
        .orderBy('id', 'desc')
        .execute();
      const files = latest.flatMap(({ path, sha256, size, rig_version }): ArtFile[] =>
        sha256 === null || size === null
          ? []
          : [{ path: ArtPath.parse(path), sha256, size, rigVersion: rig_version }],
      );
      return { generation: Math.max(0, ...latest.map(({ id }) => Number(id))), files };
    },

    async record(changes, admin) {
      // One change at a time, until its transaction commits: ids then commit in order, so the
      // newest id (the generation) never stands for a set still missing an earlier change.
      await sql`select pg_advisory_xact_lock(hashtext('art_files'))`.execute(db);
      await db
        .insertInto('art_files')
        .values(
          changes.map(({ path, file }) => ({
            path,
            sha256: file?.sha256 ?? null,
            size: file?.size ?? null,
            rig_version: file?.rigVersion ?? 1,
            changed_by: admin,
          })),
        )
        .execute();
    },
  };
}
