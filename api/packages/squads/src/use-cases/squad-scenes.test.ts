import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresSquadStore, type SquadTables } from '../adapters/postgres-squad-store.js';
import { randomInviteCodes } from '../adapters/random-invite-codes.js';
import { SceneWeek } from '../domain/scene.js';
import { MemberId, SquadId, SquadName } from '../domain/squad.js';
import { createSquadScenes } from './squad-scenes.js';
import { createSquads } from './squads.js';

/** The `index`th entry of a list a test made long enough. */
function nth<T>(list: readonly T[], index: number): T {
  const entry = list[index];
  if (entry === undefined) throw new Error(`No entry ${String(index)}.`);
  return entry;
}

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<SquadTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

const squads = createSquads({
  store: createPostgresSquadStore(db),
  inviteCodes: randomInviteCodes,
  aiConsent: () => Promise.resolve(true),
});

/** The scenes with last week's crown as the test sets it, and the week open as it sets it. */
function scenesWith(state: { crown: MemberId[]; week: string }) {
  return createSquadScenes({
    squads,
    clock: () => new Date(),
    sceneWeekAt: () => SceneWeek.parse(state.week),
    crownHolders: () => Promise.resolve(state.crown),
  });
}

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

async function squadOf(count: number) {
  const people = await Promise.all(Array.from({ length: count }, () => newMember()));
  const [captain, rest] = [nth(people, 0), people.slice(1)];
  const { squad } = await squads.create({
    id: SquadId.parse(randomUUID()),
    creator: captain,
    name: SquadName.parse('早八跑团'),
  });
  for (const member of rest) await squads.join({ inviteCode: squad.inviteCode, member });
  return { squad, people };
}

describe('picking the squad’s scene', () => {
  it('is last week’s crown winners’, any of them on a tie, once a week', async () => {
    const { squad, people } = await squadOf(3);
    const [ann, bo, cy] = [nth(people, 0), nth(people, 1), nth(people, 2)];
    const state = { crown: [bo, cy], week: '2026-10-26' };
    const scenes = scenesWith(state);

    const before = await scenes.scene({ squad: squad.id, viewer: ann });
    expect([before.pickers, before.canPick]).toStrictEqual([
      { by: 'crown', members: [bo, cy] },
      false,
    ]);
    await expect(
      scenes.pick({
        squad: squad.id,
        member: ann,
        week: SceneWeek.parse(state.week),
        scene: 'gym',
      }),
    ).rejects.toMatchObject({ reason: 'NOT_SCENE_PICKER' });
    const { scene } = await scenes.pick({
      squad: squad.id,
      member: cy,
      week: SceneWeek.parse(state.week),
      scene: 'gym',
    });
    expect([scene.scene, scene.picked?.by, scene.canPick]).toStrictEqual(['gym', cy, false]);
    await expect(
      scenes.pick({
        squad: squad.id,
        member: bo,
        week: SceneWeek.parse(state.week),
        scene: 'pool',
      }),
    ).rejects.toMatchObject({ reason: 'SCENE_ALREADY_PICKED' });

    // The next week, nobody won: the captain picks, and the gym stays until then.
    state.crown = [];
    state.week = '2026-11-02';
    const next = await scenes.scene({ squad: squad.id, viewer: ann });
    expect([next.scene, next.pickers, next.canPick, next.lastTrained.get('gym')]).toStrictEqual([
      'gym',
      { by: 'captain', members: [ann] },
      true,
      0,
    ]);
  });

  it('falls to the captain when the crown winners have left the squad', async () => {
    const { squad, people } = await squadOf(2);
    const [ann, bo] = [nth(people, 0), nth(people, 1)];
    await squads.leave({ squad: squad.id, member: bo });
    const scene = await scenesWith({ crown: [bo], week: '2026-10-26' }).scene({
      squad: squad.id,
      viewer: ann,
    });
    expect(scene.pickers).toStrictEqual({ by: 'captain', members: [ann] });
  });

  it('keeps the picks append-only, and the scene when the picker deletes their account', async () => {
    const { squad, people } = await squadOf(2);
    const [ann, bo] = [nth(people, 0), nth(people, 1)];
    const scenes = scenesWith({ crown: [bo], week: '2026-10-26' });
    await scenes.pick({
      squad: squad.id,
      member: bo,
      week: SceneWeek.parse('2026-10-26'),
      scene: 'tennis',
    });
    await expect(
      sql`update public.squad_scene_picks set scene = 'pool' where squad_id = ${squad.id}`.execute(
        db,
      ),
    ).rejects.toMatchObject({ code: '42501' });
    await expect(
      sql`delete from public.squad_scene_picks where squad_id = ${squad.id}`.execute(db),
    ).rejects.toMatchObject({ code: '42501' });
    await sql`delete from auth.users where id = ${bo}`.execute(db);
    const after = await scenes.scene({ squad: squad.id, viewer: ann });
    expect([after.scene, after.picked?.by]).toStrictEqual(['tennis', null]);
  });
});
