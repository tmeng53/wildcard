import { Kysely, PostgresDialect } from 'kysely';
import pg from 'pg';

/**
 * The tables the API reads and writes: none until the first endpoint that stores data. Their
 * types will be generated from the migrations then, not written by hand.
 */
export type Tables = Record<string, never>;

export type Database = Kysely<Tables>;

/** A connection pool to Postgres. Call `destroy()` on shutdown. */
export function createDatabase(url: string): Database {
  return new Kysely<Tables>({
    dialect: new PostgresDialect({
      pool: new pg.Pool({ connectionString: url, connectionTimeoutMillis: 5_000 }),
    }),
  });
}
