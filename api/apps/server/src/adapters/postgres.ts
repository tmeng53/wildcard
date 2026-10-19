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
  return new Kysely<Tables>({ dialect: new PostgresDialect({ pool }) });
}
