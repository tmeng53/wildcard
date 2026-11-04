import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';

import type { Database, Tables } from '../ports.js';

/**
 * The database port on any Postgres (Supabase's today): a pool. Call `destroy()` on shutdown.
 * When the server drops an idle connection (a restart, an idle timeout), the pool emits
 * `'error'`; with no listener Node would crash the process, so `onIdleError` hears it and the
 * pool opens a fresh connection on the next query.
 * https://node-postgres.com/apis/pool#error
 * With `ca` (a PEM), every connection is TLS and the server's certificate must chain to it.
 * https://node-postgres.com/features/ssl
 */
export function createDatabase(
  url: string,
  {
    ca,
    onIdleError = () => undefined,
  }: { readonly ca?: string; readonly onIdleError?: (error: Error) => void } = {},
): Database {
  const pool = new pg.Pool({
    connectionString: url,
    connectionTimeoutMillis: 5_000,
    ...(ca === undefined ? {} : { ssl: { ca } }),
  });
  pool.on('error', onIdleError);
  // A client checked out of the pool (a transaction between two queries) has none of the pool's
  // listeners, so a drop then would crash the process too. Its next query fails ("not queryable"),
  // and the request fails and is logged like any other, so this listener only keeps the process up.
  // It stays silent: idle drops reach onIdleError through the pool, and would be logged twice.
  pool.on('connect', (client) => client.on('error', () => undefined));
  return new Kysely<Tables>({ dialect: new PostgresDialect({ pool }) });
}

/**
 * Runs `work` so that its failure can't spoil the rest of `scope`: inside a transaction it gets a
 * savepoint, which a failure rolls back to before throwing, so the transaction carries on (in
 * Postgres a failed statement otherwise aborts the whole transaction). Outside one it just runs.
 * https://www.postgresql.org/docs/current/sql-savepoint.html
 */
export async function onItsOwn<T>(scope: Database, work: () => Promise<T>): Promise<T> {
  if (!scope.isTransaction) return work();
  await sql`savepoint on_its_own`.execute(scope);
  try {
    const done = await work();
    await sql`release savepoint on_its_own`.execute(scope);
    return done;
  } catch (error) {
    await sql`rollback to savepoint on_its_own`.execute(scope);
    throw error;
  }
}
