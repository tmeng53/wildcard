import type { Kysely } from 'kysely';

import { MemberId } from '../domain/ai-consent.js';
import type { ConsentStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type AiConsentTables = DB;

/** The consent store on Postgres (`supabase/migrations`). */
export function createPostgresConsentStore(db: Kysely<AiConsentTables>): ConsentStore {
  return {
    async latest(member) {
      const row = await db
        .selectFrom('ai_consents')
        .select(['copy_version', 'given_at'])
        .where('member_id', '=', member)
        .orderBy('copy_version', 'desc')
        .limit(1)
        .executeTakeFirst();
      return row === undefined
        ? undefined
        : { copyVersion: row.copy_version, givenAt: new Date(row.given_at) };
    },

    async give(member, { copyVersion, givenAt }) {
      // Two requests at once keep one consent: the first one written.
      await db
        .insertInto('ai_consents')
        .values({ member_id: member, copy_version: copyVersion, given_at: givenAt })
        .onConflict((conflict) => conflict.columns(['member_id', 'copy_version']).doNothing())
        .execute();
      const kept = await db
        .selectFrom('ai_consents')
        .select('given_at')
        .where('member_id', '=', member)
        .where('copy_version', '=', copyVersion)
        .executeTakeFirstOrThrow();
      return { copyVersion, givenAt: new Date(kept.given_at) };
    },

    async agreedTo(copyVersion, members) {
      if (members.length === 0) return new Set();
      const rows = await db
        .selectFrom('ai_consents')
        .select('member_id')
        .where('member_id', 'in', members)
        .where('copy_version', '=', copyVersion)
        .execute();
      return new Set(rows.map((row) => MemberId.parse(row.member_id)));
    },
  };
}
