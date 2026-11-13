import { sql, type Kysely } from 'kysely';

import { TeammatePushSettings } from '../domain/teammate-push-settings.js';
import type { TeammatePushSettingsStore, TeammatePushStore } from '../ports.js';
import type { DB } from './tables.js';

/** The teammate push's settings on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresTeammatePushSettings(db: Kysely<DB>): TeammatePushSettingsStore {
  return {
    async current(options) {
      const row = await db
        .selectFrom('teammate_push_settings')
        .select(['sending', 'daily_rings'])
        .$if(options?.forUpdate === true, (query) => query.forUpdate())
        .executeTakeFirstOrThrow();
      return TeammatePushSettings.parse({
        version: 1,
        sending: row.sending,
        dailyRings: row.daily_rings,
      });
    },

    async save(settings, by) {
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('teammate_push_settings')
            .set({ sending: settings.sending, daily_rings: settings.dailyRings })
            .where(
              sql<boolean>`(sending, daily_rings) is distinct from (${settings.sending}::boolean, ${settings.dailyRings}::integer)`,
            )
            .returning('only_row'),
        )
        .insertInto('teammate_push_setting_events')
        .columns(['changed_by', 'settings'])
        .expression((eb) =>
          eb
            .selectFrom('changed')
            .select([
              sql<string>`${by}::uuid`.as('changed_by'),
              sql<string>`${JSON.stringify(settings)}::jsonb`.as('settings'),
            ]),
        )
        .returning('id')
        .execute();
      return saved.length > 0;
    },
  };
}

const DAY_MS = 24 * 60 * 60 * 1000;

/** The record of teammate pushes handled, on Postgres (`supabase/migrations`). */
export function createPostgresTeammatePushStore(db: Kysely<DB>): TeammatePushStore {
  return {
    async claim({ checkIn, member, at, dailyRings }) {
      // One statement, so the count and the claim agree: it rings while fewer than `dailyRings`
      // rang for the member in the 24 hours before.
      const { rows } = await sql<{ rang: boolean }>`
        insert into public.teammate_pushes (check_in_id, member_id, at, rang)
        select ${checkIn}::uuid, ${member}::uuid, ${at}::timestamptz, (
          select count(*) from public.teammate_pushes
          where member_id = ${member}::uuid and rang
            and at > ${new Date(at.getTime() - DAY_MS)}::timestamptz
        ) < ${dailyRings}::integer
        on conflict (check_in_id, member_id) do nothing
        returning rang
      `.execute(db);
      const [claimed] = rows;
      if (claimed === undefined) return undefined;
      return claimed.rang ? 'ring' : 'silent';
    },
  };
}
