// The campaign tools over the real switches, scenes, unlock rules and campaigns in local Supabase,
// each test inside a transaction it rolls back so the seed stays as it was.
import { randomUUID } from 'node:crypto';

import { createArt, createPostgresArtStore } from '@wildcard/art';
import { createCampaigns, createPostgresCampaignStore } from '@wildcard/campaigns';
import { createPostgresSceneStore, createScenes } from '@wildcard/scenes';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { createPostgresSwitchStore, createSwitches } from '@wildcard/switches';
import { createPostgresUnlockStore, createUnlocks } from '@wildcard/unlocks';
import { AdminId } from '@wildcard/admins';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../../adapters/postgres.js';
import { UserId, type Database } from '../../ports.js';
import { mySwitches } from '../../routes/my-switches.js';
import { config } from '../../test-kit/local-supabase.js';
import { newYorkDay } from '../../new-york-day.js';
import type { AdminTool } from '../admin-tool.js';
import { campaignTools } from './campaigns.js';

const Answer = z.record(z.string(), z.unknown());

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());

class RolledBack extends Error {}

async function rolledBack(test: (trx: Database) => Promise<void>) {
  try {
    await db.transaction().execute(async (trx) => {
      await test(trx);
      throw new RolledBack();
    });
  } catch (error) {
    if (!(error instanceof RolledBack)) throw error;
  }
}

const unused = (): never => {
  throw new Error('not used here');
};

// 2026-11-06, 9am in New York.
const now = new Date('2026-11-06T14:00:00Z');

function toolsOn(trx: Database) {
  const switches = createSwitches({ store: createPostgresSwitchStore(trx) });
  const scenes = createScenes({
    store: createPostgresSceneStore(trx),
    switches: () => switches.states(),
  });
  const unlocks = createUnlocks({
    store: createPostgresUnlockStore(trx),
    trainedSince: () => Promise.resolve([]),
    sportListed: (id) => createSports({ store: createPostgresSportStore(trx) }).isListed(id),
    switches: async (member) => {
      const { on } = await switches.statesFor(member);
      return (id, at) => on(id, newYorkDay(at));
    },
  });
  const deps = {
    campaigns: createCampaigns({ store: createPostgresCampaignStore(trx) }),
    switches,
    scenes,
    unlocks,
    art: createArt({
      store: createPostgresArtStore(trx),
      blobs: {
        publicBase: new URL('https://art.test/'),
        get: unused,
        put: unused,
        uploadUrl: unused,
      },
    }),
    clock: () => now,
  };
  const tools = new Map<string, AdminTool>(campaignTools(deps).map((tool) => [tool.name, tool]));
  const run = async (
    name: string,
    { input, admin }: { readonly input: Record<string, unknown>; readonly admin: string },
  ) => {
    const tool = tools.get(name);
    if (tool === undefined) throw new Error(`no tool ${name}`);
    return Answer.parse(await tool.run(input, { admin: AdminId.parse(admin) }));
  };
  return { run, switches, scenes };
}

async function member(trx: Database) {
  const id = randomUUID();
  await sql`insert into auth.users (id) values (${id})`.execute(trx);
  return id;
}

const thanksgiving = {
  id: 'thanksgivingTest',
  label: 'Thanksgiving',
  switches: [
    { id: 'tgWeek', label: 'Thanksgiving store', window: { start: '11-24', end: '11-26' } },
    { id: 'tgDay', label: 'Thanksgiving day', window: { start: '11-26', end: '11-26' } },
  ],
  scenes: [
    {
      id: 'tgTown',
      names: { zhHans: '秋日小镇', en: 'Autumn Town', zhHant: '秋日小鎮' },
      colors: {
        signature: '#A8521F',
        onSignature: '#FFFFFF',
        wash: '#FBEFE6',
        text: '#8F4519',
        floor: '#E8D9C5',
      },
      offered: true,
      switchId: 'tgDay',
      takeover: true,
    },
  ],
  unlockRules: [
    { kind: 'piece', id: 'trot-cranberry', sports: [], after: 1, switchId: 'tgWeek' },
    { kind: 'piece', id: 'trot-pie', sports: [], after: 2, switchId: 'tgWeek' },
  ],
};

describe('a campaign', () => {
  it('starts as a draft nobody sees, previews only for previewers, then goes live', async () => {
    await rolledBack(async (trx) => {
      const { run, switches, scenes } = toolsOn(trx);
      const [admin, other] = [await member(trx), await member(trx)];

      const put = await run('put_campaign', { input: thanksgiving, admin });
      expect(put).toMatchObject({
        campaign: {
          id: 'thanksgivingTest',
          status: 'draft',
          switches: [
            { id: 'tgDay', mode: 'off', window: { start: '11-26', end: '11-26' } },
            { id: 'tgWeek', mode: 'off', window: { start: '11-24', end: '11-26' } },
          ],
          scenes: [{ id: 'tgTown', takeover: true }],
          unlockRules: [{ id: 'trot-cranberry' }, { id: 'trot-pie' }],
          missingArt: ['scenes/tgTown-day@3x.png', 'scenes/tgTown-night@3x.png'],
        },
      });
      const modes = async () =>
        Object.fromEntries(
          (await switches.list())
            .filter(({ id }) => id.startsWith('tg'))
            .map(({ id, mode }) => [id, mode]),
        );
      expect(await modes()).toEqual({ tgDay: 'off', tgWeek: 'off' });
      // A takeover scene is never one a squad picks.
      expect(await scenes.openOn('2026-11-26')).not.toContain('tgTown');

      // Without confirm, the move only says what it would do.
      const asked = await run('set_campaign_status', {
        input: { id: 'thanksgivingTest', status: 'preview' },
        admin,
      });
      expect(asked).toMatchObject({ changed: false });
      expect(asked.plan).toContain('every squad’s home shows the tgTown scene');
      expect(asked.plan).toContain('piece trot-pie unlocks after 2 练了 on these days');
      expect(asked.plan).toContain('Warning, art not uploaded yet');
      expect(await modes()).toEqual({ tgDay: 'off', tgWeek: 'off' });

      await run('set_campaign_status', {
        input: { id: 'thanksgivingTest', status: 'preview', confirm: true },
        admin,
      });
      expect(await modes()).toEqual({ tgDay: 'preview', tgWeek: 'preview' });

      // The admin pretends it is Thanksgiving; the other member sees nothing.
      expect(
        await run('set_switch_preview', { input: { preview: true, day: '2026-11-26' }, admin }),
      ).toEqual({
        version: 1,
        previewers: [{ member: admin, dayOffset: 20, day: '2026-11-26' }],
      });
      const today = newYorkDay(now);
      const takeover = async (who: string) =>
        scenes.takeover({ day: today, switchOn: (await switches.statesFor(who)).on });
      expect(await takeover(admin)).toBe('tgTown');
      expect(await takeover(other)).toBeUndefined();

      const route = mySwitches({
        verifyToken: (token) =>
          Promise.resolve({ userId: UserId.parse(token), oauthClient: undefined }),
        switches,
        clock: () => now,
      });
      const on = async (who: string) =>
        Answer.parse(
          await (
            await route.request('/me/switches', { headers: { authorization: `Bearer ${who}` } })
          ).json(),
        );
      expect(await on(admin)).toEqual({ version: 1, on: ['tgDay', 'tgWeek', 'winter'] });
      // Winter opens on 11-15: only the admin's pretend day is in it.
      expect(await on(other)).toEqual({ version: 1, on: [] });

      // Live: everyone, on its days only.
      await run('set_campaign_status', {
        input: { id: 'thanksgivingTest', status: 'live', confirm: true },
        admin,
      });
      expect(await takeover(other)).toBeUndefined();
      expect(await scenes.takeover({ day: '2026-11-26', switchOn: await switches.states() })).toBe(
        'tgTown',
      );

      // Stopped: nobody, previewers included.
      await run('set_campaign_status', {
        input: { id: 'thanksgivingTest', status: 'stopped', confirm: true },
        admin,
      });
      expect(await modes()).toEqual({ tgDay: 'off', tgWeek: 'off' });
      expect(await takeover(admin)).toBeUndefined();

      const { rows } = await sql<{ status: string }>`
        select value->>'status' as status from public.events
        where event_id = 'thanksgivingTest' order by id
      `.execute(trx);
      expect(rows.map(({ status }) => status)).toEqual(['draft', 'preview', 'live', 'stopped']);
    });
  });

  it('refuses a scene or rule that follows a switch the campaign doesn’t own', async () => {
    await rolledBack(async (trx) => {
      const { run } = toolsOn(trx);
      const admin = await member(trx);
      await expect(
        run('put_campaign', {
          input: {
            ...thanksgiving,
            unlockRules: [{ ...thanksgiving.unlockRules[0], switchId: 'winter' }],
          },
          admin,
        }),
      ).rejects.toThrow(/follows one of the campaign’s switches/);
    });
  });

  it('keeps its status when it is changed again', async () => {
    await rolledBack(async (trx) => {
      const { run, switches } = toolsOn(trx);
      const admin = await member(trx);
      await run('put_campaign', { input: thanksgiving, admin });
      await run('set_campaign_status', {
        input: { id: 'thanksgivingTest', status: 'live', confirm: true },
        admin,
      });
      await run('put_campaign', { input: { ...thanksgiving, label: 'Thanksgiving 2026' }, admin });
      const week = (await switches.list()).find(({ id }) => id === 'tgWeek');
      expect(week?.mode).toBe('schedule');
    });
  });
});
