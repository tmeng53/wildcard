import { sql, type Kysely } from 'kysely';

import type { AiUsageLedger } from '../ports.js';
import type { DB } from './tables.js';

/** Every model call on Postgres, append-only (`supabase/migrations`). */
export function createPostgresAiUsageLedger(db: Kysely<DB>): AiUsageLedger {
  return {
    async record({ feature, squad, member, model, usage, costMicros, at }) {
      await db
        .insertInto('ai_usage')
        .values({
          feature,
          // A squad that ended meanwhile, or an account deleted meanwhile, leaves the call
          // unnamed, as their deletion would have.
          squad_id:
            squad === undefined
              ? null
              : sql<string | null>`(select id from public.squads where id = ${squad}::uuid)`,
          member_id:
            member === undefined
              ? null
              : sql<string | null>`(select id from auth.users where id = ${member}::uuid)`,
          model,
          requests: usage.requests,
          input_tokens: usage.inputTokens,
          cached_input_tokens: Math.min(usage.cachedInputTokens, usage.inputTokens),
          output_tokens: usage.outputTokens,
          cost_micros: costMicros,
          at,
        })
        .execute();
    },

    async spent({ squad, since }) {
      const row = await db
        .selectFrom('ai_usage')
        .select((eb) =>
          eb.fn.coalesce(eb.fn.sum<string>('cost_micros'), sql<string>`0`).as('spent'),
        )
        .where('at', '>=', since)
        .$if(squad !== undefined, (query) => query.where('squad_id', '=', squad ?? ''))
        .executeTakeFirstOrThrow();
      return Number(row.spent);
    },

    async total({ squad, features, since }) {
      const row = await db
        .selectFrom('ai_usage')
        .select((eb) => [
          eb.fn.countAll<string>().as('calls'),
          sql<string>`coalesce(sum(requests), 0)`.as('requests'),
          sql<string>`coalesce(sum(input_tokens), 0)`.as('input_tokens'),
          sql<string>`coalesce(sum(cached_input_tokens), 0)`.as('cached_input_tokens'),
          sql<string>`coalesce(sum(output_tokens), 0)`.as('output_tokens'),
          sql<string>`coalesce(sum(cost_micros), 0)`.as('cost_micros'),
        ])
        .where('squad_id', '=', squad)
        .where('feature', 'in', [...features])
        .$if(since !== undefined, (query) => query.where('at', '>=', since ?? new Date(0)))
        .executeTakeFirstOrThrow();
      return {
        calls: Number(row.calls),
        requests: Number(row.requests),
        inputTokens: Number(row.input_tokens),
        cachedInputTokens: Number(row.cached_input_tokens),
        outputTokens: Number(row.output_tokens),
        costMicros: Number(row.cost_micros),
      };
    },
  };
}
