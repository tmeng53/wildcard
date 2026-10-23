import { sql, type Kysely } from 'kysely';

import { DEFAULT_PUSH_SETTINGS, PushTopic } from '../domain/topic.js';
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
      const switches = sql.join(
        PushTopic.options.map(
          (topic) =>
            sql`(${topic}, ${settings[topic]}::boolean, ${DEFAULT_PUSH_SETTINGS[topic]}::boolean)`,
        ),
      );
      // One statement: the switches and their log entries are saved together. A switch gets a
      // row only once it leaves its default, and only a switch that changed is logged.
      await db
        .with('saved', (cte) =>
          cte
            .insertInto('push_settings')
            .columns(['member_id', 'topic', 'enabled'])
            .expression(
              sql`select ${member}::uuid, s.topic, s.enabled
                from (values ${switches}) as s (topic, enabled, default_enabled)
                where s.enabled <> s.default_enabled or exists (
                  select 1 from public.push_settings
                  where push_settings.member_id = ${member} and push_settings.topic = s.topic
                )`,
            )
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
