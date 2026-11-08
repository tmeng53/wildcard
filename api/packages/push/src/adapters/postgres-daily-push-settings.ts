import { sql, type Kysely } from 'kysely';

import { DailyPushSettings } from '../domain/daily-push-settings.js';
import type { DailyPushSettingsStore } from '../ports.js';
import type { DB } from './tables.js';

/** The daily push's settings on Postgres: one row, and its log (`supabase/migrations`). */
export function createPostgresDailyPushSettings(db: Kysely<DB>): DailyPushSettingsStore {
  return {
    async current(options) {
      const row = await db
        .selectFrom('daily_push_settings')
        .select([
          'sending',
          'hour',
          'plan_reminder_sending',
          'plan_reminder_hour',
          'plan_reminder_minute',
        ])
        .$if(options?.forUpdate === true, (query) => query.forUpdate())
        .executeTakeFirstOrThrow();
      return DailyPushSettings.parse({
        version: 2,
        sending: row.sending,
        hour: row.hour,
        planReminderSending: row.plan_reminder_sending,
        planReminderHour: row.plan_reminder_hour,
        planReminderMinute: row.plan_reminder_minute,
      });
    },

    async save(settings, by) {
      const columns = {
        sending: settings.sending,
        hour: settings.hour,
        plan_reminder_sending: settings.planReminderSending,
        plan_reminder_hour: settings.planReminderHour,
        plan_reminder_minute: settings.planReminderMinute,
      };
      // One statement: the row changes only when something differs, and the log gets the whole
      // new value exactly when it does.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .updateTable('daily_push_settings')
            .set(columns)
            .where(
              sql<boolean>`(sending, hour, plan_reminder_sending, plan_reminder_hour, plan_reminder_minute) is distinct from (${settings.sending}::boolean, ${settings.hour}::integer, ${settings.planReminderSending}::boolean, ${settings.planReminderHour}::integer, ${settings.planReminderMinute}::integer)`,
            )
            .returning('only_row'),
        )
        .insertInto('daily_push_setting_events')
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
