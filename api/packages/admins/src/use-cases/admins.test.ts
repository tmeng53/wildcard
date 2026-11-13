import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresAdminStore, type AdminTables } from '../adapters/postgres-admin-store.js';
import { ToolName } from '../domain/admin-action.js';
import { DemoAccountNotFoundError, NotAnAdminError } from '../errors.js';
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

  it('lists everyone on the admin list, and no one else', async () => {
    const [admin, other] = [await member({ admin: true }), await member({ admin: false })];
    const listed = new Set<string>(await admins.list());
    expect([listed.has(admin), listed.has(other)]).toStrictEqual([true, false]);
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

  describe('demo accounts', () => {
    it('lists an admin’s demo accounts oldest first, and switches only between them', async () => {
      const admin = await admins.requireAdmin(await member({ admin: true }));
      const [first, second, stranger] = [
        await member({ admin: false }),
        await member({ admin: false }),
        await member({ admin: false }),
      ];
      now = new Date('2026-11-13T09:00:00.000Z');
      await admins.addDemoAccount(admin, first);
      now = new Date('2026-11-13T09:01:00.000Z');
      await admins.addDemoAccount(admin, second);

      expect(await admins.demoAccounts(admin)).toStrictEqual([first, second]);
      expect(await admins.requireDemoAccount(admin, second)).toBe(second);
      await expect(admins.requireDemoAccount(admin, stranger)).rejects.toThrow(
        DemoAccountNotFoundError,
      );
      await expect(admins.requireDemoAccount(admin, admin)).rejects.toThrow(
        DemoAccountNotFoundError,
      );
    });

    it('lets the admin and their demo accounts switch, and no one else', async () => {
      const admin = await admins.requireAdmin(await member({ admin: true }));
      const [demo, other] = [await member({ admin: false }), await member({ admin: false })];
      await admins.addDemoAccount(admin, demo);

      expect([await admins.demoOwner(admin), await admins.demoOwner(demo)]).toStrictEqual([
        admin,
        admin,
      ]);
      await expect(admins.demoOwner(other)).rejects.toThrow(NotAnAdminError);
      expect([await admins.isDemoAccount(demo), await admins.isDemoAccount(admin)]).toStrictEqual([
        true,
        false,
      ]);
    });

    it('is never changed, and goes with the account', async () => {
      const admin = await admins.requireAdmin(await member({ admin: true }));
      const demo = await member({ admin: false });
      await admins.addDemoAccount(admin, demo);

      await expect(
        sql`delete from public.admin_demo_accounts where member_id = ${demo}`.execute(db),
      ).rejects.toThrow('append-only');
      await sql`delete from auth.users where id = ${demo}`.execute(db);
      expect(await admins.demoAccounts(admin)).toStrictEqual([]);
    });

    it('goes with the admin’s account too', async () => {
      const admin = await admins.requireAdmin(await member({ admin: true }));
      const demo = await member({ admin: false });
      await admins.addDemoAccount(admin, demo);

      await sql`delete from auth.users where id = ${admin}`.execute(db);
      expect(await admins.isDemoAccount(demo)).toBe(false);
    });

    it('stops switching for an admin taken off the list, from their demo accounts too', async () => {
      const admin = await admins.requireAdmin(await member({ admin: true }));
      const demo = await member({ admin: false });
      await admins.addDemoAccount(admin, demo);

      await db.deleteFrom('admins').where('member_id', '=', admin).execute();
      await expect(admins.demoOwner(demo)).rejects.toThrow(NotAnAdminError);
    });
  });
});
