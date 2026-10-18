import { Kysely, PostgresDialect } from 'kysely';
import pg from 'pg';

import type { Database, Tables } from '../ports.js';

/** The database port on any Postgres (Supabase's today): a pool. Call `destroy()` on shutdown. */
export function createDatabase(url: string): Database {
  return new Kysely<Tables>({
    dialect: new PostgresDialect({
      pool: new pg.Pool({ connectionString: url, connectionTimeoutMillis: 5_000 }),
    }),
  });
}
