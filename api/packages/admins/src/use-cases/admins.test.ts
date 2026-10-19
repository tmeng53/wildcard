import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresAdminStore, type AdminTables } from '../adapters/postgres-admin-store.js';
import { ToolName } from '../domain/admin-action.js';
import { NotAnAdminError } from '../errors.js';
import { createAdmins } from './admins.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<AdminTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

let now = new Date('2026-10-19T04:00:00.000Z');
const admins = createAdmins({ store: createPostgresAdminStore(db), clock: () => now });

/** A new member in auth.users, on the admin list when asked. */
async function member(options: { admin: boolean }) {
  const id = randomUUID();
  await sql`insert into auth.users (id, email) values (${id}, ${`${id}@example.com`})`.execute(db);
  if (options.admin) await db.insertInto('admins').values({ member_id: id }).execute();
  return id;
}

describe('admins', () => {
  it('lets a member on the admin list in', async () => {
    const id = await member({ admin: true });
    expect(await admins.requireAdmin(id)).toBe(id);
  });

  it('turns away a member who is not on the list', async () => {
    const id = await member({ admin: false });
    await expect(admins.requireAdmin(id)).rejects.toThrow(NotAnAdminError);
  });

  it('logs each change with who, when and what, and lists them newest first', async () => {
    const admin = await admins.requireAdmin(await member({ admin: true }));
    const tool = ToolName.parse('turn_off_meme');
    await admins.logChange({ admin, tool, arguments: { memeId: 'm1' } });
    now = new Date('2026-10-19T05:00:00.000Z');
    await admins.logChange({ admin, tool, arguments: { memeId: 'm2' } });

    expect(await admins.listLog({ admin, limit: 10 })).toStrictEqual([
      {
        admin,
        at: new Date('2026-10-19T05:00:00.000Z'),
        action: { version: 1, tool: 'turn_off_meme', arguments: { memeId: 'm2' } },
      },
      {
        admin,
        at: new Date('2026-10-19T04:00:00.000Z'),
        action: { version: 1, tool: 'turn_off_meme', arguments: { memeId: 'm1' } },
      },
    ]);
    expect(await admins.listLog({ admin, limit: 1 })).toHaveLength(1);
  });

  it('logs only JSON arguments', async () => {
    const admin = await admins.requireAdmin(await member({ admin: true }));
    await expect(
      admins.logChange({
        admin,
        tool: ToolName.parse('turn_off_meme'),
        arguments: { when: new Date() },
      }),
    ).rejects.toThrow(z.ZodError);
    expect(await admins.listLog({ admin, limit: 10 })).toStrictEqual([]);
  });
});
