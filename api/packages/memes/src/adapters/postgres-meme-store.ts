import type { Kysely } from 'kysely';

import { MemeId, StoredMeme, storedPayload, type MemeRecord } from '../domain/meme.js';
import type { MemeStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type MemeTables = DB;

/** The meme store on Postgres (`supabase/migrations`). */
export function createPostgresMemeStore(db: Kysely<MemeTables>): MemeStore {
  return {
    async add(memes, approvedAt) {
      if (memes.length === 0) return [];
      const rows = await db
        .insertInto('memes')
        .values(
          memes.map((meme) => ({
            phrase: meme.phrase,
            payload: JSON.stringify(storedPayload(meme)),
            approved_at: approvedAt,
          })),
        )
        .onConflict((conflict) => conflict.column('phrase').doNothing())
        .returning('phrase')
        .execute();
      return rows.map(({ phrase }) => phrase);
    },

    async listApprovedBetween({ from, to }) {
      const rows = await db
        .selectFrom('memes')
        .select(['id', 'phrase', 'payload', 'approved_at'])
        .where('approved_at', '>=', from)
        .where('approved_at', '<=', to)
        .where('disabled_at', 'is', null)
        .orderBy('approved_at', 'desc')
        .orderBy('phrase')
        .execute();
      return rows.map((row): MemeRecord => {
        const { background, meaning, styles, source } = StoredMeme.parse(row.payload);
        return {
          id: MemeId.parse(row.id),
          phrase: row.phrase,
          background,
          meaning,
          styles,
          source,
          approvedAt: row.approved_at,
        };
      });
    },

    async turnOff(phrase, at) {
      const row = await db
        .updateTable('memes')
        // Turning a meme off twice keeps the first time.
        .set((eb) => ({ disabled_at: eb.fn.coalesce('disabled_at', eb.val(at)) }))
        .where('phrase', '=', phrase)
        .returning('id')
        .executeTakeFirst();
      return row !== undefined;
    },

    async turnOn(phrase) {
      const row = await db
        .updateTable('memes')
        .set({ disabled_at: null })
        .where('phrase', '=', phrase)
        .returning('id')
        .executeTakeFirst();
      return row !== undefined;
    },
  };
}
