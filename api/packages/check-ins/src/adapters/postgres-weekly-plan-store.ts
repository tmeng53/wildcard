import { sql, type Kysely } from 'kysely';

import { StoredPlan, WeekStart } from '../domain/weekly-plan.js';
import type { WeeklyPlanStore } from '../ports.js';
import type { DB } from './tables.js';

/** The weekly plan store on Postgres (`supabase/migrations`). */
export function createPostgresWeeklyPlanStore(db: Kysely<DB>): WeeklyPlanStore {
  return {
    async latestFrom(member, weekStart) {
      const row = await db
        .selectFrom('weekly_plans')
        // A `date` read as text: node-postgres would turn it into a Date at local midnight.
        .select([sql<string>`week_start::text`.as('week_start'), 'payload'])
        .where('member_id', '=', member)
        .where('week_start', '<=', weekStart)
        .orderBy('week_start', 'desc')
        .limit(1)
        .executeTakeFirst();
      if (row === undefined) return undefined;
      return {
        weekStart: WeekStart.parse(row.week_start),
        days: StoredPlan.parse(row.payload).days,
      };
    },

    async save({ member, weekStart, days }) {
      const payload = JSON.stringify({ version: 1, days });
      // One statement: the plan and its log entry are saved together, and a save that
      // changes nothing writes neither.
      await db
        .with('saved', (cte) =>
          cte
            .insertInto('weekly_plans')
            .values({ member_id: member, week_start: weekStart, payload })
            .onConflict((conflict) =>
              conflict
                .columns(['member_id', 'week_start'])
                .doUpdateSet({ payload })
                .where(sql<boolean>`weekly_plans.payload is distinct from excluded.payload`),
            )
            .returning(['member_id', 'week_start', 'payload']),
        )
        .insertInto('weekly_plan_events')
        .columns(['member_id', 'week_start', 'payload'])
        .expression((eb) => eb.selectFrom('saved').select(['member_id', 'week_start', 'payload']))
        .execute();
    },
  };
}
