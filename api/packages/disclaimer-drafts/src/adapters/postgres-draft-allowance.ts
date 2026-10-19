import { sql, type Kysely } from 'kysely';
import { z } from 'zod';

import type { DraftAllowance, Reservation } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this module reads and writes, as generated from the migrations. */
export type DisclaimerDraftTables = DB;

const ReservationId = z
  .uuid()
  .transform((id): Reservation => z.uuid().brand<'Reservation'>().parse(id));

/** The draft allowance on Postgres (`supabase/migrations`). */
export function createPostgresDraftAllowance(db: Kysely<DisclaimerDraftTables>): DraftAllowance {
  return {
    reserve: ({ member, at, since, limit }) =>
      db.transaction().execute(async (trx) => {
        // One member's requests are counted one at a time, so two at once can't both take the
        // last one.
        await sql`select pg_advisory_xact_lock(hashtext('disclaimer_draft_requests'), hashtext(${member}))`.execute(
          trx,
        );
        await trx
          .deleteFrom('disclaimer_draft_requests')
          .where('member_id', '=', member)
          .where('requested_at', '<=', since)
          .execute();
        const { count } = await trx
          .selectFrom('disclaimer_draft_requests')
          .select((eb) => eb.fn.countAll<string>().as('count'))
          .where('member_id', '=', member)
          .executeTakeFirstOrThrow();
        if (Number(count) >= limit) return undefined;
        const { id } = await trx
          .insertInto('disclaimer_draft_requests')
          .values({ member_id: member, requested_at: at })
          .returning('id')
          .executeTakeFirstOrThrow();
        return ReservationId.parse(id);
      }),
    release: async (reservation) => {
      await db.deleteFrom('disclaimer_draft_requests').where('id', '=', reservation).execute();
    },
  };
}
