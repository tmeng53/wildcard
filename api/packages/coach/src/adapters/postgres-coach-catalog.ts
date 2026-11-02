import { sql, type Kysely } from 'kysely';

import { Coach } from '../domain/coach.js';
import type { CoachCatalogStore } from '../ports.js';
import type { DB } from './tables.js';

/** A coach from its row. */
function coachOf(row: DB['coaches']): Coach {
  return Coach.parse({
    version: 2,
    id: row.id,
    tier: row.tier,
    name: row.name,
    title: row.title,
    catchphrase: row.catchphrase,
    background: row.background,
    yearsCoaching: row.years_coaching,
    experience: row.experience,
    tags: row.tags,
    pay: row.pay,
    style: row.style,
    soul: row.soul,
    look: row.look,
    offered: row.offered,
  });
}

/** The coaches on Postgres, each change logged (`supabase/migrations`). */
export function createPostgresCoachCatalog(db: Kysely<DB>): CoachCatalogStore {
  return {
    async list() {
      const rows = await db.selectFrom('coaches').selectAll().orderBy('id').execute();
      return rows.map(coachOf);
    },

    async save(coach, by) {
      const columns = {
        tier: coach.tier,
        name: coach.name,
        title: coach.title,
        catchphrase: coach.catchphrase,
        background: coach.background,
        years_coaching: coach.yearsCoaching,
        experience: coach.experience,
        tags: [...coach.tags],
        pay: coach.pay,
        style: coach.style,
        soul: coach.soul,
        look: coach.look,
        offered: coach.offered,
      };
      // One statement: a new coach is added, a listed one changes only when something differs,
      // and the log gets the whole new value exactly when either happens.
      const saved = await db
        .with('changed', (cte) =>
          cte
            .insertInto('coaches')
            .values({ id: coach.id, ...columns })
            .onConflict((conflict) =>
              conflict
                .column('id')
                .doUpdateSet(columns)
                .where(
                  sql<boolean>`(coaches.tier, coaches.name, coaches.title, coaches.catchphrase, coaches.background, coaches.years_coaching, coaches.experience, coaches.tags, coaches.pay, coaches.style, coaches.soul, coaches.look, coaches.offered) is distinct from (excluded.tier, excluded.name, excluded.title, excluded.catchphrase, excluded.background, excluded.years_coaching, excluded.experience, excluded.tags, excluded.pay, excluded.style, excluded.soul, excluded.look, excluded.offered)`,
                ),
            )
            .returning('id'),
        )
        .insertInto('coach_catalog_events')
        .columns(['changed_by', 'coach_id', 'coach'])
        .expression((eb) =>
          eb
            .selectFrom('changed')
            .select([
              sql<string>`${by}::uuid`.as('changed_by'),
              'changed.id',
              sql<string>`${JSON.stringify(coach)}::jsonb`.as('coach'),
            ]),
        )
        .returning('id')
        .execute();
      return saved.length > 0;
    },
  };
}
