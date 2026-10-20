import type { Kysely } from 'kysely';

import { AiConsentTerms, MemberId } from '../domain/ai-consent.js';
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
        .select(['copy_version', 'provider', 'given_at'])
        .where('member_id', '=', member)
        .where('withdrawn_at', 'is', null)
        .orderBy('given_at', 'desc')
        .limit(1)
        .executeTakeFirst();
      return row === undefined
        ? undefined
        : {
            terms: AiConsentTerms.parse({ copyVersion: row.copy_version, provider: row.provider }),
            givenAt: new Date(row.given_at),
          };
    },

    async give(member, { terms, givenAt }) {
      await db
        .insertInto('ai_consents')
        .values({
          member_id: member,
          copy_version: terms.copyVersion,
          provider: terms.provider,
          given_at: givenAt,
        })
        .execute();
    },

    async withdraw(member, at) {
      await db
        .updateTable('ai_consents')
        .set({ withdrawn_at: at })
        .where('member_id', '=', member)
        .where('withdrawn_at', 'is', null)
        .execute();
    },

    async consentingTo(terms, members) {
      if (members.length === 0) return new Set();
      const rows = await db
        .selectFrom('ai_consents')
        .distinctOn('member_id')
        .select(['member_id', 'copy_version', 'provider'])
        .where('member_id', 'in', members)
        .where('withdrawn_at', 'is', null)
        .orderBy('member_id')
        .orderBy('given_at', 'desc')
        .execute();
      return new Set(
        rows
          .filter(
            (row) => row.copy_version === terms.copyVersion && row.provider === terms.provider,
          )
          .map((row) => MemberId.parse(row.member_id)),
      );
    },
  };
}
