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
      // One statement: the switches and their log entries are saved together, and only the
      // switches that changed are logged.
      await db
        .with('saved', (cte) =>
          cte
            .insertInto('push_settings')
            .values(rows)
            .onConflict((conflict) =>
              conflict
                .columns(['member_id', 'topic'])
                .doUpdateSet({ enabled: (eb) => eb.ref('excluded.enabled') })
                .where(sql<boolean>`push_settings.enabled is distinct from excluded.enabled`),
            )
            .returning(['member_id', 'topic', 'enabled']),
        )
        .insertInto('push_setting_events')
        .columns(['member_id', 'topic', 'enabled'])
        .expression((eb) => eb.selectFrom('saved').select(['member_id', 'topic', 'enabled']))
        .execute();
    },
  };
}
