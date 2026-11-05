import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresSwitchStore, type SwitchTables } from '../adapters/postgres-switch-store.js';
import { addDays, createSwitches } from './switches.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Each test changes the seeded
// switches inside a transaction it rolls back, so other test files keep reading the seed.
const db = new Kysely<SwitchTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

class RolledBack extends Error {}

async function rolledBack(test: (trx: Kysely<SwitchTables>) => Promise<void>) {
  await expect(
    db.transaction().execute(async (trx) => {
      await test(trx);
      throw new RolledBack();
    }),
  ).rejects.toBeInstanceOf(RolledBack);
}

async function logCount(trx: Kysely<SwitchTables>) {
  const { rows } = await sql<{ n: number }>`
    select count(*)::int as n from public.switch_events
  `.execute(trx);
  return rows[0]?.n ?? 0;
}

describe('the switches', () => {
  it('start with winter, on every year from November 15 to March 31', async () => {
    const switches = createSwitches({ store: createPostgresSwitchStore(db) });
    expect(await switches.list()).toContainEqual({
      id: 'winter',
      label: '雪场 and POWDER DAY',
      mode: 'schedule',
      window: { start: '11-15', end: '03-31' },
    });
    const on = await switches.states();
    expect([
      on('winter', '2026-11-14'),
      on('winter', '2026-12-01'),
      on('moon', '2026-12-01'),
    ]).toEqual([false, true, false]);
  });

  it('turns one on, off or back to its schedule, each change logged once', async () => {
    await rolledBack(async (trx) => {
      const switches = createSwitches({ store: createPostgresSwitchStore(trx) });
      const before = await logCount(trx);
      await switches.put({
        id: 'winter',
        label: 'Winter',
        mode: 'off',
        window: { start: '11-15', end: '03-31' },
      });
      expect((await switches.states())('winter', '2026-12-01')).toBe(false);
      await switches.put({
        id: 'winter',
        label: 'Winter',
        mode: 'off',
        window: { start: '11-15', end: '03-31' },
      });
      const added = await switches.put({ id: 'summer', label: 'Summer', mode: 'on' });
      expect(added.find(({ id }) => id === 'summer')).toStrictEqual({
        id: 'summer',
        label: 'Summer',
        mode: 'on',
      });
      expect((await logCount(trx)) - before).toBe(2);
    });
  });

  it('never deletes a switch or changes its id', async () => {
    await expect(db.deleteFrom('switches').where('id', '=', 'winter').execute()).rejects.toThrow(
      /never deleted/,
    );
    await expect(
      db.updateTable('switches').set({ id: 'winter2' }).where('id', '=', 'winter').execute(),
    ).rejects.toThrow(/never changes/);
  });

  it('shows a switch in preview only to previewers, on the day each pretends it is', async () => {
    await rolledBack(async (trx) => {
      const switches = createSwitches({ store: createPostgresSwitchStore(trx) });
      const [admin, other] = [randomUUID(), randomUUID()];
      await sql`insert into auth.users (id) values (${admin}), (${other})`.execute(trx);
      await switches.put({
        id: 'thanksgiving',
        label: 'Thanksgiving',
        mode: 'preview',
        window: { start: '11-24', end: '11-26' },
      });
      expect(await switches.previewers()).toEqual([]);
      expect(
        await switches.setView({
          member: admin,
          view: { previewer: true, dayOffset: 18 },
          by: admin,
        }),
      ).toEqual([{ member: admin, dayOffset: 18 }]);

      const seen = await switches.statesFor(admin);
      // 11-06 plus 18 days is 11-24, the first day of the window.
      expect(seen.on('thanksgiving', '2026-11-06')).toBe(true);
      expect(seen.on('thanksgiving', '2026-11-05')).toBe(false);
      expect((await switches.statesFor(other)).on('thanksgiving', '2026-11-24')).toBe(false);
      expect((await switches.states())('thanksgiving', '2026-11-24')).toBe(false);

      // Taking them off brings back the real day, and a repeat writes nothing.
      await switches.setView({
        member: admin,
        view: { previewer: false, dayOffset: 0 },
        by: admin,
      });
      await switches.setView({
        member: admin,
        view: { previewer: false, dayOffset: 0 },
        by: admin,
      });
      expect(await switches.previewers()).toEqual([]);
      expect((await switches.statesFor(admin)).on('thanksgiving', '2026-11-24')).toBe(false);
      const { rows } = await sql<{ n: number }>`
        select count(*)::int as n from public.switch_previews where member_id = ${admin}
      `.execute(trx);
      expect(rows[0]?.n).toBe(2);
    });
  });

  it('moves a day by whole days, across months and years', () => {
    expect(addDays('2026-11-06', 18)).toBe('2026-11-24');
    expect(addDays('2026-12-30', 3)).toBe('2027-01-02');
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28');
  });
});
