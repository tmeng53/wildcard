import { readFileSync } from 'node:fs';

import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';

import { config } from '../test-kit/local-supabase.js';
import { createDatabase } from './postgres.js';

const admin = createDatabase(config.databaseUrl);
afterAll(async () => {
  await admin.destroy();
});

describe('createDatabase', () => {
  it('hears a dropped idle connection and keeps working', async () => {
    const heard: Error[] = [];
    const db = createDatabase(config.databaseUrl, { onIdleError: (error) => heard.push(error) });
    const tag = `idle-drop-${String(Date.now())}`;
    await sql`select set_config('application_name', ${tag}, false)`.execute(db);

    // The connection is back in the pool, idle; the server ends it as a restart would.
    await sql`select pg_terminate_backend(pid) from pg_stat_activity where application_name = ${tag}`.execute(
      admin,
    );
    await expect.poll(() => heard.length).toBe(1);

    const { rows } = await sql<{ one: number }>`select 1 as one`.execute(db);
    expect(rows).toStrictEqual([{ one: 1 }]);
    await db.destroy();
  });

  it('survives a connection dropped inside a transaction, whose next query fails', async () => {
    const db = createDatabase(config.databaseUrl);
    const tag = `busy-drop-${String(Date.now())}`;
    const transaction = db.transaction().execute(async (trx) => {
      await sql`select set_config('application_name', ${tag}, false)`.execute(trx);
      // The transaction holds the connection, between queries, as the server ends it.
      await sql`select pg_terminate_backend(pid) from pg_stat_activity where application_name = ${tag}`.execute(
        admin,
      );
      await new Promise((resolve) => setTimeout(resolve, 200));
      await sql`select 1`.execute(trx);
    });
    await expect(transaction).rejects.toThrow(/not queryable/);

    const { rows } = await sql<{ one: number }>`select 1 as one`.execute(db);
    expect(rows).toStrictEqual([{ one: 1 }]);
    await db.destroy();
  });

  it('insists on TLS once given a CA, never falling back to a plain connection', async () => {
    // Local Supabase's database has no TLS, so a connection that must use it is refused.
    const ca = readFileSync(new URL('../../certs/supabase-root-2021.crt', import.meta.url), 'utf8');
    const db = createDatabase(config.databaseUrl, { ca });
    await expect(sql`select 1`.execute(db)).rejects.toThrow(/does not support SSL/);
    await db.destroy();
  });
});
