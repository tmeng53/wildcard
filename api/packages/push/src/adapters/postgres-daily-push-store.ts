import { sql, type Kysely } from 'kysely';

import { LocalDay } from '../domain/daily.js';
import { MemberId } from '../domain/device.js';
import type { PushTopic } from '../domain/topic.js';
import type { DailyPushStore } from '../ports.js';
import type { DB } from './tables.js';

const TOPIC: PushTopic = 'dailyProgress';

/** The daily push store on Postgres (`supabase/migrations`). */
export function createPostgresDailyPushStore(db: Kysely<DB>): DailyPushStore {
  /** Of these members, those who haven't turned the daily push off. */
  async function switchedOn(members: readonly string[]): Promise<MemberId[]> {
    const off = await db
      .selectFrom('push_settings')
      .select('member_id')
      .where('member_id', 'in', members)
      .where('topic', '=', TOPIC)
      .where('enabled', '=', false)
      .execute();
    const switchedOff = new Set(off.map(({ member_id }) => member_id));
    return members
      .filter((member) => !switchedOff.has(member))
      .map((member) => MemberId.parse(member));
  }

  return {
    async due(candidates) {
      if (candidates.length === 0) return [];
      const dayOf = new Map(candidates.map(({ member, day }) => [member, day]));
      // Members without a phone are due too: their push reaches no phone, but it is still kept
      // in their 通知, so turning notifications off in iOS loses no history.
      const on = await switchedOn([...dayOf.keys()]);
      if (on.length === 0) return [];
      const handled = await db
        .selectFrom('daily_pushes')
        .select(['member_id', sql<string>`day::text`.as('day')])
        .where('member_id', 'in', on)
        .where('day', 'in', [...new Set(on.flatMap((member) => dayOf.get(member) ?? []))])
        .execute();
      const done = new Set(handled.map(({ member_id, day }) => `${member_id} ${day}`));
      const due = on.filter((member) => !done.has(`${member} ${dayOf.get(member) ?? ''}`));
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

    async planReminderDue(candidates) {
      if (candidates.length === 0) return [];
      const weekOf = new Map(candidates.map(({ member, week }) => [member, week]));
      // As with the daily push, members without a phone are due too, for their 通知.
      const on = await switchedOn([...weekOf.keys()]);
      if (on.length === 0) return [];
      const handled = await db
        .selectFrom('plan_reminder_pushes')
        .select(['member_id', sql<string>`week_start::text`.as('week')])
        .where('member_id', 'in', on)
        .where('week_start', 'in', [...new Set(on.flatMap((member) => weekOf.get(member) ?? []))])
        .execute();
      const done = new Set(handled.map(({ member_id, week }) => `${member_id} ${week}`));
      return on.flatMap((member) => {
        const week = weekOf.get(member);
        return week === undefined || done.has(`${member} ${week}`) ? [] : [{ member, week }];
      });
    },

    async claimPlanReminder({ member, week, at }) {
      const row = await db
        .insertInto('plan_reminder_pushes')
        .values({ member_id: member, week_start: LocalDay.parse(week), handled_at: at })
        .onConflict((conflict) => conflict.columns(['member_id', 'week_start']).doNothing())
        .returning('member_id')
        .executeTakeFirst();
      return row !== undefined;
    },
  };
}
