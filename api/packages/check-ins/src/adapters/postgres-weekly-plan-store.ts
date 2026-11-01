import { sql, type Kysely } from 'kysely';

import { StoredFuelGoals } from '../domain/fuel-goal.js';
import { StoredPlan, WeekStart } from '../domain/weekly-plan.js';
import type { WeeklyPlanStore } from '../ports.js';
import type { DB } from './tables.js';

/** The weekly plan, template and 饮食小目标 store on Postgres (`supabase/migrations`). */
export function createPostgresWeeklyPlanStore(db: Kysely<DB>): WeeklyPlanStore {
  return {
    async savedFor(member, weekStart) {
      const row = await db
        .selectFrom('weekly_plans')
        .select('payload')
        .where('member_id', '=', member)
        .where('week_start', '=', weekStart)
        .executeTakeFirst();
      return row === undefined ? undefined : StoredPlan.parse(row.payload).days;
    },

    async templateFor(member, weekStart) {
      const row = await db
        .selectFrom('plan_templates')
        .select('payload')
        .where('member_id', '=', member)
        .where('from_week', '<=', weekStart)
        // The newest change that applies, even over an older one applying from a later week.
        .orderBy('id', 'desc')
        .limit(1)
        .executeTakeFirst();
      return row === undefined ? undefined : StoredPlan.parse(row.payload).days;
    },

    async latestTemplate(member) {
      const row = await db
        .selectFrom('plan_templates')
        // A `date` read as text: node-postgres would turn it into a Date at local midnight.
        .select([sql<string>`from_week::text`.as('from_week'), 'payload'])
        .where('member_id', '=', member)
        .orderBy('id', 'desc')
        .limit(1)
        .executeTakeFirst();
      if (row === undefined) return undefined;
      return {
        fromWeek: WeekStart.parse(row.from_week),
        days: StoredPlan.parse(row.payload).days,
      };
    },

    async saveTemplate({ member, fromWeek, days }) {
      const payload = JSON.stringify({ version: 1, days });
      // A save equal to the latest writes nothing.
      await sql`
        insert into plan_templates (member_id, from_week, payload)
        select ${member}, ${fromWeek}::date, ${payload}::jsonb
        where (
          select payload from plan_templates
          where member_id = ${member} order by id desc limit 1
        ) is distinct from ${payload}::jsonb
      `.execute(db);
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

    async fuelGoals(member, weekStart) {
      const row = await db
        .selectFrom('fuel_goals')
        .select('payload')
        .where('member_id', '=', member)
        .where('week_start', '=', weekStart)
        .executeTakeFirst();
      return row === undefined ? undefined : StoredFuelGoals.parse(row.payload).goals;
    },

    async saveFuelGoals({ member, weekStart, goals }) {
      const payload = JSON.stringify({ version: 1, goals });
      // As with the plan: one statement, and a save that changes nothing writes neither. No row
      // already means no goals, so clearing a week that has none only updates a row that exists.
      await db
        .with('saved', (cte) =>
          goals.length === 0
            ? cte
                .updateTable('fuel_goals')
                .set({ payload })
                .where('member_id', '=', member)
                .where('week_start', '=', weekStart)
                .where(sql<boolean>`fuel_goals.payload is distinct from ${payload}::jsonb`)
                .returning(['member_id', 'week_start', 'payload'])
            : cte
                .insertInto('fuel_goals')
                .values({ member_id: member, week_start: weekStart, payload })
                .onConflict((conflict) =>
                  conflict
                    .columns(['member_id', 'week_start'])
                    .doUpdateSet({ payload })
                    .where(sql<boolean>`fuel_goals.payload is distinct from excluded.payload`),
                )
                .returning(['member_id', 'week_start', 'payload']),
        )
        .insertInto('fuel_goal_events')
        .columns(['member_id', 'week_start', 'payload'])
        .expression((eb) => eb.selectFrom('saved').select(['member_id', 'week_start', 'payload']))
        .execute();
    },
  };
}
