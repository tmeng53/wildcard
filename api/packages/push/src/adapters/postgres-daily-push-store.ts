import { sql, type Kysely } from 'kysely';

import { LocalDay } from '../domain/daily.js';
import { MemberId } from '../domain/device.js';
import type { PushTopic } from '../domain/topic.js';
import type { DailyPushStore } from '../ports.js';
import type { DB } from './tables.js';

const TOPIC: PushTopic = 'dailyProgress';

/** The daily push store on Postgres (`supabase/migrations`). */
export function createPostgresDailyPushStore(db: Kysely<DB>): DailyPushStore {
  return {
    async due(candidates) {
      if (candidates.length === 0) return [];
      const dayOf = new Map(candidates.map(({ member, day }) => [member, day]));
      const rows = await db
        .selectFrom('push_devices')
        .select('push_devices.member_id')
        .distinct()
        .where('push_devices.member_id', 'in', [...dayOf.keys()])
        .where((eb) =>
          eb.not(
            eb.exists(
              eb
                .selectFrom('push_settings')
                .select('push_settings.member_id')
                .whereRef('push_settings.member_id', '=', 'push_devices.member_id')
                .where('push_settings.topic', '=', TOPIC)
                .where('push_settings.enabled', '=', false),
            ),
          ),
        )
        .execute();
      const withPhone = rows.map((row) => MemberId.parse(row.member_id));
      if (withPhone.length === 0) return [];
      const handled = await db
        .selectFrom('daily_pushes')
        .select(['member_id', sql<string>`day::text`.as('day')])
        .where('member_id', 'in', withPhone)
        .where('day', 'in', [...new Set(withPhone.flatMap((member) => dayOf.get(member) ?? []))])
        .execute();
      const done = new Set(handled.map(({ member_id, day }) => `${member_id} ${day}`));
      const due = withPhone.filter((member) => !done.has(`${member} ${dayOf.get(member) ?? ''}`));
      if (due.length === 0) return [];
      const last = await db
        .selectFrom('daily_pushes')
        .select(['member_id', (eb) => eb.fn.max('handled_at').as('handled_at')])
        .where('member_id', 'in', due)
        .groupBy('member_id')
        .execute();
      const lastOf = new Map(last.map((row) => [row.member_id, new Date(row.handled_at)]));
      return due.flatMap((member) => {
        const day = dayOf.get(member);
        return day === undefined ? [] : [{ member, day, lastHandledAt: lastOf.get(member) }];
      });
    },

    async claim({ member, day, quiet, at }) {
      const row = await db
        .insertInto('daily_pushes')
        .values({ member_id: member, day: LocalDay.parse(day), quiet, handled_at: at })
        .onConflict((conflict) => conflict.columns(['member_id', 'day']).doNothing())
        .returning('member_id')
        .executeTakeFirst();
      return row !== undefined;
    },
  };
}
