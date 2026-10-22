import { sql, type Kysely } from 'kysely';

import { PushTopic } from '../domain/topic.js';
import type { SettingsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The push settings store on Postgres (`supabase/migrations`). */
export function createPostgresSettingsStore(db: Kysely<DB>): SettingsStore {
  return {
    async changedBy(member) {
      const rows = await db
        .selectFrom('push_settings')
        .select(['topic', 'enabled'])
        .where('member_id', '=', member)
        .execute();
      // A topic this release no longer has is left out, not an error.
      return new Map(
        rows.flatMap(({ topic, enabled }) => {
          const known = PushTopic.safeParse(topic);
          return known.success ? [[known.data, enabled] as const] : [];
        }),
      );
    },

    async save(member, settings) {
      const rows = PushTopic.options.map((topic) => ({
        member_id: member,
        topic,
        enabled: settings[topic],
      }));
      await db
        .insertInto('push_settings')
        .values(rows)
        .onConflict((conflict) =>
          conflict.columns(['member_id', 'topic']).doUpdateSet({
            enabled: (eb) => eb.ref('excluded.enabled'),
            updated_at: sql`now()`,
          }),
        )
        .execute();
    },
  };
}
