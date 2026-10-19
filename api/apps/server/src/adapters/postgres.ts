import { Kysely, PostgresDialect } from 'kysely';
import pg from 'pg';

import type { Database, Tables } from '../ports.js';

/**
 * The database port on any Postgres (Supabase's today): a pool. Call `destroy()` on shutdown.
 * When the server drops an idle connection (a restart, an idle timeout), the pool emits
 * `'error'`; with no listener Node would crash the process, so `onIdleError` hears it and the
 * pool opens a fresh connection on the next query.
 * https://node-postgres.com/apis/pool#error
 */
export function createDatabase(
  url: string,
  { onIdleError = () => undefined }: { readonly onIdleError?: (error: Error) => void } = {},
): Database {
  const pool = new pg.Pool({ connectionString: url, connectionTimeoutMillis: 5_000 });
  pool.on('error', onIdleError);
  // A client checked out of the pool (a transaction between two queries) has none of the pool's
  // listeners, so a drop then would crash the process too. Its next query fails ("not queryable"),
  // and the request fails and is logged like any other, so this listener only keeps the process up.
  // It stays silent: idle drops reach onIdleError through the pool, and would be logged twice.
  pool.on('connect', (client) => client.on('error', () => undefined));
  return new Kysely<Tables>({ dialect: new PostgresDialect({ pool }) });
}
