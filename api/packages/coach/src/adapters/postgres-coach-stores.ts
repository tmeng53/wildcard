import { hasErrorCode } from '@wildcard/errors';
import { sql, type Kysely } from 'kysely';

import { CoachId } from '../domain/coach.js';
import { memberOfPath } from '../domain/memory.js';
import { SquadId } from '../domain/settings.js';
import type { Wake } from '../domain/wake.js';
import type {
  CoachActivityStore,
  CoachReportStore,
  CoachStores,
  CoachTransaction,
  UsageTotal,
} from '../ports.js';
import type { DB } from './tables.js';

/** How long a claimed wake may run before another run takes it back. */
const STALE_MINUTES = 15;

/** How old a waiting wake may be and still run; older ones are left. */
const FRESH_HOURS = 24;

/** How long a wake whose try failed waits before its next. */
const RETRY_MINUTES = 5;

/** Postgres's code for a duplicate row: here, a second running wake of a squad. */
const UNIQUE_VIOLATION = '23505';

/** A claimed wake's row as the coach reads it. */
function wakeOf(row: {
  readonly id: string;
  readonly squad_id: string;
  readonly reason: string;
  readonly check_in_id: string | null;
  readonly day: string | null;
}): Wake {
  const squad = SquadId.parse(row.squad_id);
  const id = Number(row.id);
  if (row.reason === 'daily' && row.day !== null) {
    return { id, squad, reason: { kind: 'daily', day: row.day } };
  }
  // The database keeps a check-in wake's check-in.
  return { id, squad, reason: { kind: 'checkIn', checkIn: row.check_in_id ?? '' } };
}

/** The coach's wakes, files, notes and usage on Postgres (`supabase/migrations`). */
export function createPostgresCoachStores(db: Kysely<DB>): CoachStores {
  return {
    wakes: {
      async enqueue(wakes, now) {
        let added = 0;
        for (const { squad, reason } of wakes) {
          const inserted = await db
            .insertInto('coach_wakes')
            .values(
              reason.kind === 'checkIn'
                ? {
                    squad_id: squad,
                    reason: 'checkIn',
                    check_in_id: reason.checkIn,
                    created_at: now,
                  }
                : { squad_id: squad, reason: 'daily', day: reason.day, created_at: now },
            )
            .onConflict((conflict) =>
              reason.kind === 'checkIn'
                ? conflict
                    .columns(['squad_id', 'check_in_id'])
                    .where('reason', '=', 'checkIn')
                    .doNothing()
                : conflict.columns(['squad_id', 'day']).where('reason', '=', 'daily').doNothing(),
            )
            .returning('id')
            .execute();
          added += inserted.length;
        }
        return added;
      },

      async claim({ squads, limit, now }) {
        if (squads.length === 0) return [];
        const stale = new Date(now.getTime() - STALE_MINUTES * 60_000);
        const fresh = new Date(now.getTime() - FRESH_HOURS * 3_600_000);
        const retry = new Date(now.getTime() - RETRY_MINUTES * 60_000);
        // A run that stopped on its last try leaves nothing to take back: it failed.
        await db
          .updateTable('coach_wakes')
          .set({ state: 'failed', last_error: 'the run stopped before it ended' })
          .where('state', '=', 'running')
          .where('claimed_at', '<', stale)
          .where('tries', '>=', 3)
          .execute();
        // Which wake can run: one a run must have dropped, or one waiting long enough.
        const claimable = (prefix: '' | 'wake.') =>
          sql<boolean>`${sql.ref(`${prefix}tries`)} < 3 and (
            (${sql.ref(`${prefix}state`)} = 'running' and ${sql.ref(`${prefix}claimed_at`)} < ${stale})
            or (${sql.ref(`${prefix}state`)} = 'waiting' and ${sql.ref(`${prefix}created_at`)} > ${fresh}
              and (${sql.ref(`${prefix}claimed_at`)} is null or ${sql.ref(`${prefix}claimed_at`)} < ${retry})))`;
        // Each squad's next wake: one a run dropped first, else its oldest waiting one; never
        // a squad whose wake is running.
        const next = await db
          .selectFrom('coach_wakes as wake')
          .distinctOn('wake.squad_id')
          .select(['wake.id', 'wake.squad_id', 'wake.created_at'])
          .where('wake.squad_id', 'in', squads)
          .where(claimable('wake.'))
          .where((where) =>
            where.not(
              where.exists(
                where
                  .selectFrom('coach_wakes as running')
                  .select('running.id')
                  .whereRef('running.squad_id', '=', 'wake.squad_id')
                  .where('running.state', '=', 'running')
                  .where('running.claimed_at', '>=', stale),
              ),
            ),
          )
          .orderBy('wake.squad_id')
          .orderBy(sql`wake.state = 'running'`, 'desc')
          .orderBy('wake.created_at')
          .orderBy('wake.id')
          .execute();
        const picked = next
          .toSorted((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime())
          .slice(0, limit);
        const claimed: Wake[] = [];
        for (const { id } of picked) {
          // Claimed only if it still can be: another run may have taken it, or another of its
          // squad's wakes, which the one-running-a-squad index refuses.
          const row = await db
            .updateTable('coach_wakes')
            .set((eb) => ({ state: 'running', tries: eb('tries', '+', 1), claimed_at: now }))
            .where('id', '=', id)
            .where(claimable(''))
            .returning([
              'id',
              'squad_id',
              'reason',
              'check_in_id',
              sql<string | null>`to_char(day, 'YYYY-MM-DD')`.as('day'),
            ])
            .executeTakeFirst()
            .catch((error: unknown) => {
              if (hasErrorCode(error, UNIQUE_VIOLATION)) return undefined;
              throw error;
            });
          if (row !== undefined) claimed.push(wakeOf(row));
        }
        return claimed;
      },

      async finish(wake) {
        await db
          .updateTable('coach_wakes')
          .set({ state: 'done', last_error: null })
          .where('id', '=', String(wake))
          .execute();
      },

      async fail(wake, error) {
        await db
          .updateTable('coach_wakes')
          .set((eb) => ({
            state: eb.case().when('tries', '>=', 3).then('failed').else('waiting').end(),
            last_error: error.slice(0, 1000),
          }))
          .where('id', '=', String(wake))
          .execute();
      },
    },

    memory: {
      async files(squad) {
        const rows = await db
          .selectFrom('coach_files')
          .distinctOn('path')
          .select(['path', 'body'])
          .where('squad_id', '=', squad)
          .orderBy('path')
          .orderBy('id', 'desc')
          .execute();
        return new Map(rows.map(({ path, body }) => [path, body]));
      },

      async save({ squad, wake, files }) {
        if (files.length === 0) return;
        await db
          .insertInto('coach_files')
          .values(
            files.map(({ path, body }) => ({
              squad_id: squad,
              path,
              member_id: memberOfPath(path) ?? null,
              body,
              wake_id: String(wake),
            })),
          )
          .execute();
      },
    },

    notes: {
      async save({ squad, coach, day, text, wake }) {
        const saved = await db
          .insertInto('coach_notes')
          .values({ squad_id: squad, coach_id: coach, day, text, wake_id: String(wake) })
          .onConflict((conflict) => conflict.columns(['squad_id', 'day']).doNothing())
          .returning('id')
          .execute();
        return saved.length > 0;
      },

      async recent(squad, limit) {
        return db
          .selectFrom('coach_notes')
          .select([sql<string>`to_char(day, 'YYYY-MM-DD')`.as('day'), 'text'])
          .where('squad_id', '=', squad)
          .orderBy('coach_notes.day', 'desc')
          .limit(limit)
          .execute();
      },
    },

    replies: {
      async save({ squad, checkIn, coach, text, emoji, wake }) {
        // Nothing when the check-in went while the run was thinking: a failed insert would undo
        // the rest of the wake's save with it.
        const saved = await sql<{ id: string }>`
          insert into public.coach_replies (squad_id, check_in_id, coach_id, text, emoji, wake_id)
          select ${squad}, id, ${coach}, ${text ?? null}, ${emoji ?? null}, ${String(wake)}
          from public.check_ins where id = ${checkIn}
          on conflict (squad_id, check_in_id) do nothing
          returning id`.execute(db);
        return saved.rows.length > 0;
      },
    },

    usage: {
      async record({ squad, wake, coach, model, usage, costMicros }) {
        await db
          .insertInto('coach_usage')
          .values({
            squad_id: squad,
            // Null when the wake has gone meanwhile (its check-in was deleted).
            wake_id: (eb) =>
              eb.selectFrom('coach_wakes').select('id').where('id', '=', String(wake)),
            coach_id: coach,
            model,
            requests: usage.requests,
            input_tokens: usage.inputTokens,
            cached_input_tokens: usage.cachedInputTokens,
            output_tokens: usage.outputTokens,
            cost_micros: costMicros,
          })
          .execute();
      },
    },
  };
}

/** What a squad's coaches have said, read from Postgres for its members. */
export function createPostgresCoachActivity(db: Kysely<DB>): CoachActivityStore {
  return {
    async latestNote(squad) {
      const row = await db
        .selectFrom('coach_notes')
        .innerJoin('coaches', 'coaches.id', 'coach_notes.coach_id')
        .select([
          sql<string>`to_char(coach_notes.day, 'YYYY-MM-DD')`.as('day'),
          'coach_notes.text',
          'coach_notes.at',
          'coaches.id as coach_id',
          'coaches.name',
          'coaches.look',
        ])
        .where('coach_notes.squad_id', '=', squad)
        .orderBy('coach_notes.day', 'desc')
        .limit(1)
        .executeTakeFirst();
      if (row === undefined) return undefined;
      return {
        day: row.day,
        text: row.text,
        coach: { id: row.coach_id, name: row.name, look: row.look },
        at: new Date(row.at),
      };
    },

    async replies(squad, checkIns) {
      if (checkIns.length === 0) return [];
      const rows = await db
        .selectFrom('coach_replies')
        .innerJoin('coaches', 'coaches.id', 'coach_replies.coach_id')
        .select([
          'coach_replies.check_in_id',
          'coach_replies.text',
          'coach_replies.emoji',
          'coach_replies.at',
          'coaches.id as coach_id',
          'coaches.name',
          'coaches.look',
        ])
        .where('coach_replies.squad_id', '=', squad)
        .where('coach_replies.check_in_id', 'in', checkIns)
        .execute();
      return rows.map((row) => ({
        checkIn: row.check_in_id,
        coach: { id: row.coach_id, name: row.name, look: row.look },
        text: row.text ?? undefined,
        emoji: row.emoji ?? undefined,
        at: new Date(row.at),
      }));
    },
  };
}

/** Runs work on the coach's stores in one Postgres transaction. */
export function postgresCoachTransaction(db: Kysely<DB>): CoachTransaction {
  return (work) => db.transaction().execute((trx) => work(createPostgresCoachStores(trx)));
}

/** What a squad's coach has done, read from Postgres for the admins. */
export function createPostgresCoachReport(db: Kysely<DB>): CoachReportStore {
  return {
    async squad(squad, now) {
      const files = await db
        .selectFrom('coach_files')
        .distinctOn('path')
        .select(['path', 'body', 'at'])
        .where('squad_id', '=', squad)
        .orderBy('path')
        .orderBy('id', 'desc')
        .execute();
      const notes = await db
        .selectFrom('coach_notes')
        .select([sql<string>`to_char(day, 'YYYY-MM-DD')`.as('day'), 'text'])
        .where('squad_id', '=', squad)
        .orderBy('coach_notes.day', 'desc')
        .limit(14)
        .execute();
      const wakes = await db
        .selectFrom('coach_wakes')
        .select(['reason', 'state', 'tries', 'last_error', 'created_at'])
        .where('squad_id', '=', squad)
        .orderBy('id', 'desc')
        .limit(20)
        .execute();
      const weekAgo = new Date(now.getTime() - 7 * 86_400_000);
      const totalSince = async (since: Date | undefined): Promise<UsageTotal> => {
        const row = await db
          .selectFrom('coach_usage')
          .select((eb) => [
            eb.fn.countAll<string>().as('wakes'),
            sql<string>`coalesce(sum(requests), 0)`.as('requests'),
            sql<string>`coalesce(sum(input_tokens), 0)`.as('input_tokens'),
            sql<string>`coalesce(sum(cached_input_tokens), 0)`.as('cached_input_tokens'),
            sql<string>`coalesce(sum(output_tokens), 0)`.as('output_tokens'),
            sql<string>`coalesce(sum(cost_micros), 0)`.as('cost_micros'),
          ])
          .where('squad_id', '=', squad)
          .$if(since !== undefined, (query) => query.where('at', '>=', since ?? now))
          .executeTakeFirstOrThrow();
        return {
          wakes: Number(row.wakes),
          requests: Number(row.requests),
          inputTokens: Number(row.input_tokens),
          cachedInputTokens: Number(row.cached_input_tokens),
          outputTokens: Number(row.output_tokens),
          costMicros: Number(row.cost_micros),
        };
      };
      const hired = await db
        .selectFrom('squad_coaches')
        .select('coach_id')
        .where('squad_id', '=', squad)
        .executeTakeFirst();
      return {
        version: 1,
        coach: hired === undefined ? null : CoachId.parse(hired.coach_id),
        files: files.map(({ path, body, at }) => ({ path, body, at: new Date(at) })),
        notes,
        wakes: wakes.map((wake) => ({
          reason: wake.reason === 'daily' ? 'daily' : 'checkIn',
          state: wake.state,
          tries: wake.tries,
          lastError: wake.last_error,
          createdAt: new Date(wake.created_at),
        })),
        usage: { total: await totalSince(undefined), lastWeek: await totalSince(weekAgo) },
      };
    },
  };
}
