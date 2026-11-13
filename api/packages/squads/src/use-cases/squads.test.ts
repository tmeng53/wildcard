import { NEW_YORK } from '@wildcard/time-zones';
import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresSquadStore, type SquadTables } from '../adapters/postgres-squad-store.js';
import { randomInviteCodes } from '../adapters/random-invite-codes.js';
import { InviteCode } from '../domain/invite-code.js';
import { MemberId, SquadId, SquadName } from '../domain/squad.js';
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

// Who has a current AI consent, as the AI consent module would answer: every new member,
// unless a test makes one without.
const consented = new Set<MemberId>();
const aiConsent = (member: MemberId) => Promise.resolve(consented.has(member));
const squads = createSquads({
  store: createPostgresSquadStore(db),
  inviteCodes: randomInviteCodes,
  aiConsent,
});

async function newMember({ consentsToAi = true } = {}) {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  if (consentsToAi) consented.add(id);
  return id;
}

const name = (text: string) => SquadName.parse(text);

async function newSquad(creator: MemberId, text = '早八跑团') {
  const { squad } = await squads.create({
    timeZone: NEW_YORK,
    week: '2026-11-02',
    id: SquadId.parse(randomUUID()),
    creator,
    name: name(text),
  });
  await openToJoin(squad.id, creator);
  return squad;
}

/** A join that let the member in, as every squad here lets members straight in. */
function inSquad(outcome: Awaited<ReturnType<typeof squads.join>>) {
  if (!('squad' in outcome)) throw new Error('Asked the captain instead of joining.');
  return outcome;
}

/** Turns the captain's OK to join off (入队需要审核), so members join straight in. */
async function openToJoin(squad: SquadId, captain: MemberId) {
  await squads.setJoinApproval({ squad, member: captain, required: false });
}

describe('creating a squad', () => {
  it('saves it with only a name and the creator as its one member', async () => {
    const creator = await newMember();
    const id = SquadId.parse(randomUUID());
    const { squad, created } = await squads.create({
      timeZone: NEW_YORK,
      week: '2026-11-02',
      id,
      creator,
      name: name(' 早八跑团 '),
    });
    expect(created).toBe(true);
    expect({ ...squad, inviteCode: undefined, createdAt: undefined }).toStrictEqual({
      id,
      name: '早八跑团',
      inviteCode: undefined,
      createdAt: undefined,
      createdBy: creator,
      captain: creator,
      members: [{ member: creator, joinedAt: squad.members[0]?.joinedAt }],
    });
    expect(squad.inviteCode).toMatch(/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$/);
  });

  it('answers a retry with the squad already made, and refuses another name or member', async () => {
    const creator = await newMember();
    const id = SquadId.parse(randomUUID());
    const first = await squads.create({
      timeZone: NEW_YORK,
      week: '2026-11-02',
      id,
      creator,
      name: name('早八跑团'),
    });
    const retry = await squads.create({
      timeZone: NEW_YORK,
      week: '2026-11-02',
      id,
      creator,
      name: name('早八跑团'),
    });
    expect([retry.created, retry.squad]).toStrictEqual([false, first.squad]);
    await expect(
      squads.create({ timeZone: NEW_YORK, week: '2026-11-02', id, creator, name: name('夜跑团') }),
    ).rejects.toMatchObject({
      reason: 'SQUAD_ID_CONFLICT',
    });
    await expect(
      squads.create({
        timeZone: NEW_YORK,
        week: '2026-11-02',
        id,
        creator: await newMember(),
        name: name('早八跑团'),
      }),
    ).rejects.toMatchObject({ reason: 'SQUAD_ID_CONFLICT' });
  });

  it('tries a new invite code when the first is taken', async () => {
    const taken = (await newSquad(await newMember())).inviteCode;
    const fresh = InviteCode.parse('22222222');
    await sql`delete from public.squads where invite_code = ${fresh}`.execute(db);
    const codes = [taken, fresh];
    const retrying = createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: () => codes.shift() ?? fresh,
      aiConsent,
    });
    const { squad } = await retrying.create({
      timeZone: NEW_YORK,
      week: '2026-11-02',
      id: SquadId.parse(randomUUID()),
      creator: await newMember(),
      name: name('夜跑团'),
    });
    expect([squad.inviteCode, codes]).toStrictEqual([fresh, []]);
  });

  it('refuses a member without a current AI consent', async () => {
    const member = await newMember({ consentsToAi: false });
    await expect(newSquad(member)).rejects.toMatchObject({ reason: 'AI_CONSENT_REQUIRED' });
    expect(await squads.listMine(member)).toStrictEqual([]);
  });

  it('answers a retry as before once the creator’s consent is to an older copy', async () => {
    const creator = await newMember();
    const squad = await newSquad(creator);
    consented.delete(creator);
    const again = await squads.create({
      timeZone: NEW_YORK,
      week: '2026-11-02',
      id: squad.id,
      creator,
      name: squad.name,
    });
    expect([again.created, again.squad]).toStrictEqual([false, squad]);
    await expect(newSquad(creator)).rejects.toMatchObject({ reason: 'AI_CONSENT_REQUIRED' });
  });

  it('refuses a second squad, and allows one again after leaving', async () => {
    const member = await newMember();
    const first = await newSquad(member);
    await expect(newSquad(member)).rejects.toMatchObject({ reason: 'SQUAD_LIMIT_REACHED' });
    await squads.leave({ squad: first.id, member });
    await expect(newSquad(member)).resolves.toMatchObject({ name: '早八跑团' });
  });

  it('never lets a member past one squad, however many creates arrive at once', async () => {
    const member = await newMember();
    const results = await Promise.allSettled(Array.from({ length: 6 }, () => newSquad(member)));
    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    expect(await squads.listMine(member)).toHaveLength(1);
  });
});

describe('joining by invite code', () => {
  it('adds the member after the others, typed in any case and with a dash', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(ann);
    const typed = `${squad.inviteCode.slice(0, 4).toLowerCase()}-${squad.inviteCode.slice(4)}`;
    const { squad: joined, joined: isNew } = inSquad(
      await squads.join({ inviteCode: InviteCode.parse(typed), member: bo }),
    );
    expect([isNew, joined.members.map(({ member }) => member)]).toStrictEqual([true, [ann, bo]]);
    const again = inSquad(await squads.join({ inviteCode: squad.inviteCode, member: bo }));
    expect([again.joined, again.squad]).toStrictEqual([false, joined]);
  });

  it('refuses a member without a current AI consent', async () => {
    const squad = await newSquad(await newMember());
    const member = await newMember({ consentsToAi: false });
    await expect(squads.join({ inviteCode: squad.inviteCode, member })).rejects.toMatchObject({
      reason: 'AI_CONSENT_REQUIRED',
    });
    expect((await squads.membersOf(squad.id)).includes(member)).toBe(false);
  });

  it('answers a repeat join as before once their consent is to an older copy', async () => {
    const squad = await newSquad(await newMember());
    const member = await newMember();
    await squads.join({ inviteCode: squad.inviteCode, member });
    consented.delete(member);
    const again = inSquad(await squads.join({ inviteCode: squad.inviteCode, member }));
    expect(again.joined).toBe(false);
  });

  it('asks the captain by default, unless the switch is off for everyone', async () => {
    const [ann, bo, cy] = [await newMember(), await newMember(), await newMember()];
    const { squad } = await squads.create({
      timeZone: NEW_YORK,
      week: '2026-11-02',
      id: SquadId.parse(randomUUID()),
      creator: ann,
      name: name('周三不练腿'),
    });
    const asked = await squads.join({ inviteCode: squad.inviteCode, member: bo });
    expect(asked).toMatchObject({ asked: true, request: { squad: squad.id, member: bo } });
    const switchedOff = createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent,
      joinApprovalOn: () => Promise.resolve(false),
    });
    const joined = inSquad(await switchedOff.join({ inviteCode: squad.inviteCode, member: cy }));
    expect(joined.squad.members.map(({ member }) => member)).toStrictEqual([ann, cy]);
  });

  it('refuses a code no squad has', async () => {
    await expect(
      squads.join({ inviteCode: InviteCode.parse('ZZZZZZZZ'), member: await newMember() }),
    ).rejects.toMatchObject({ reason: 'INVITE_CODE_UNKNOWN' });
  });

  it('takes 8 members and refuses a ninth, even when they all arrive at once', async () => {
    const creator = await newMember();
    const squad = await newSquad(creator);
    const joiners = await Promise.all(Array.from({ length: 10 }, () => newMember()));
    const results = await Promise.allSettled(
      joiners.map((member) => squads.join({ inviteCode: squad.inviteCode, member })),
    );
    const refused = results.flatMap((result) =>
      result.status === 'rejected'
        ? [z.object({ reason: z.string() }).parse(result.reason).reason]
        : [],
    );
    expect(refused).toStrictEqual(['SQUAD_FULL', 'SQUAD_FULL', 'SQUAD_FULL']);
    const full = await squads.find({ squad: squad.id, viewer: creator });
    expect(full.members).toHaveLength(8);
  });

  it('refuses a member already in a squad, and lets them in once they leave it', async () => {
    const member = await newMember();
    const own = await newSquad(member);
    const other = await newSquad(await newMember());
    await expect(squads.join({ inviteCode: other.inviteCode, member })).rejects.toMatchObject({
      reason: 'SQUAD_LIMIT_REACHED',
    });
    await squads.leave({ squad: own.id, member });
    await expect(squads.join({ inviteCode: other.inviteCode, member })).resolves.toMatchObject({
      joined: true,
    });
  });

  it('previews the squad with its members but not its id', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(ann, '周末网球');
    expect(await squads.previewInvite({ inviteCode: squad.inviteCode, viewer: bo })).toStrictEqual({
      name: '周末网球',
      memberCount: 1,
      full: false,
      daysPerMember: 3,
      members: [ann],
      joined: false,
      needsApproval: false,
    });
    expect(await squads.previewInvite({ inviteCode: squad.inviteCode, viewer: ann })).toMatchObject(
      {
        joined: true,
      },
    );
  });

  it('previews the squad to anyone with its name, size, whether it is full and its members', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(ann, '周末网球');
    await squads.join({ inviteCode: squad.inviteCode, member: bo });
    expect(await squads.previewPublicInvite(squad.inviteCode)).toStrictEqual({
      name: '周末网球',
      memberCount: 2,
      full: false,
      daysPerMember: 3,
      members: [ann, bo],
    });
    await expect(squads.previewPublicInvite(InviteCode.parse('ZZZZZZZZ'))).rejects.toMatchObject({
      reason: 'INVITE_CODE_UNKNOWN',
    });
  });
});

describe('leaving and listing', () => {
  it('lists my squad, and leaving takes it out', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const first = await newSquad(ann, '一');
    const second = await newSquad(bo, '二');
    expect((await squads.listMine(ann)).map((squad) => squad.name)).toStrictEqual(['一']);
    await squads.leave({ squad: first.id, member: ann });
    await squads.leave({ squad: first.id, member: ann });
    expect(await squads.listMine(ann)).toStrictEqual([]);
    await squads.join({ inviteCode: second.inviteCode, member: ann });
    expect((await squads.listMine(ann)).map((squad) => squad.name)).toStrictEqual(['二']);
  });

  it('logs each join and leave, in order, and never a leave that changed nothing', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(bo);
    const log = async () =>
      (
        await sql<{ member: string; kind: string }>`select member_id as member, kind
          from public.squad_membership_events where squad_id = ${squad.id} order by id`.execute(db)
      ).rows;
    await squads.join({ inviteCode: squad.inviteCode, member: ann });
    await squads.leave({ squad: squad.id, member: ann });
    await squads.leave({ squad: squad.id, member: ann });
    await squads.join({ inviteCode: squad.inviteCode, member: ann });
    // Joining again while in it changes nothing, so it logs nothing.
    await squads.join({ inviteCode: squad.inviteCode, member: ann });
    await squads.leave({ squad: squad.id, member: ann });
    expect(await log()).toStrictEqual([
      { member: bo, kind: 'joined' },
      { member: ann, kind: 'joined' },
      { member: ann, kind: 'left' },
      { member: ann, kind: 'joined' },
      { member: ann, kind: 'left' },
    ]);
    expect(await squads.membersOf(squad.id)).toStrictEqual([bo]);
  });

  it('keeps the log append-only', async () => {
    const ann = await newMember();
    const squad = await newSquad(ann);
    await expect(
      sql`update public.squad_membership_events set kind = 'left' where squad_id = ${squad.id}`.execute(
        db,
      ),
    ).rejects.toMatchObject({ code: '42501' });
    await expect(
      sql`delete from public.squad_membership_events where squad_id = ${squad.id}`.execute(db),
    ).rejects.toMatchObject({ code: '42501' });
  });

  it('shows a squad only to its members, the same way whether or not it exists', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(ann);
    await expect(squads.find({ squad: squad.id, viewer: bo })).rejects.toMatchObject({
      reason: 'SQUAD_NOT_JOINED',
    });
    await expect(
      squads.find({ squad: SquadId.parse(randomUUID()), viewer: bo }),
    ).rejects.toMatchObject({ reason: 'SQUAD_NOT_JOINED' });
    await squads.leave({ squad: squad.id, member: ann });
    await expect(squads.find({ squad: squad.id, viewer: ann })).rejects.toMatchObject({
      reason: 'SQUAD_NOT_JOINED',
    });
  });

  it('ends a squad whose last member leaves, keeping it since check-ins may point at it', async () => {
    const [ann, bo, cy] = [await newMember(), await newMember(), await newMember()];
    const squad = await newSquad(ann);
    const other = await newSquad(cy);
    await squads.join({ inviteCode: squad.inviteCode, member: bo });
    await squads.leave({ squad: squad.id, member: ann });
    expect(await squads.endedAmong([squad.id, other.id])).toStrictEqual(new Map());
    await squads.leave({ squad: squad.id, member: bo });
    const rows = await sql`select 1 from public.squads where id = ${squad.id}`.execute(db);
    expect(rows.rows).toHaveLength(1);
    const ended = await squads.endedAmong([squad.id, other.id]);
    expect([...ended.keys()]).toStrictEqual([squad.id]);
    // The last one out ends it, in the squad's log, with who it was.
    const { rows: log } = await sql<{ actor_id: string; kind: string; captain_id: string | null }>`
      select actor_id, kind, captain_id from public.squad_events
      where squad_id = ${squad.id} order by id desc limit 1`.execute(db);
    expect(log).toStrictEqual([{ actor_id: bo, kind: 'ended', captain_id: null }]);
    await expect(squads.join({ inviteCode: squad.inviteCode, member: ann })).rejects.toMatchObject({
      reason: 'INVITE_CODE_UNKNOWN',
    });
    await expect(squads.previewPublicInvite(squad.inviteCode)).rejects.toMatchObject({
      reason: 'INVITE_CODE_UNKNOWN',
    });
    // It stays ended, and nobody is put back in it.
    await expect(
      sql`update public.squads set ended_at = null where id = ${squad.id}`.execute(db),
    ).rejects.toMatchObject({ code: '42501' });
    await expect(
      sql`insert into public.squad_members (squad_id, member_id) values (${squad.id}, ${ann})`.execute(
        db,
      ),
    ).rejects.toMatchObject({ code: '42501' });
  });
});

describe('the captain', () => {
  async function squadOf(count: number) {
    const people = await Promise.all(Array.from({ length: count }, () => newMember()));
    const [captain, ...rest] = people;
    if (captain === undefined) throw new Error('No members.');
    const squad = await newSquad(captain);
    for (const member of rest) await squads.join({ inviteCode: squad.inviteCode, member });
    return { squad, people };
  }

  async function settingsLog(squad: SquadId) {
    const { rows } = await sql<{
      actor_id: string | null;
      kind: string;
      name: string;
      captain_id: string | null;
    }>`
      select actor_id, kind, name, captain_id from public.squad_events where squad_id = ${squad} order by id
    `.execute(db);
    return rows;
  }

  it('renames the squad, and logs each change with who made it and the full new settings', async () => {
    const { squad, people } = await squadOf(2);
    const [ann, bo] = [nth(people, 0), nth(people, 1)];
    const renamed = await squads.rename({ squad: squad.id, member: ann, name: name(' 夜跑团 ') });
    expect(renamed.name).toBe('夜跑团');
    await squads.rename({ squad: squad.id, member: ann, name: name('夜跑团') });
    await expect(
      squads.rename({ squad: squad.id, member: bo, name: name('乱改') }),
    ).rejects.toMatchObject({ reason: 'NOT_SQUAD_CAPTAIN' });
    expect(await settingsLog(squad.id)).toStrictEqual([
      { actor_id: ann, kind: 'created', name: '早八跑团', captain_id: ann },
      { actor_id: ann, kind: 'renamed', name: '夜跑团', captain_id: ann },
    ]);
  });

  it('hands the captaincy on only to a member, and only from the captain', async () => {
    const { squad, people } = await squadOf(3);
    const [ann, bo, cy] = [nth(people, 0), nth(people, 1), nth(people, 2)];
    await expect(
      squads.handCaptaincy({ squad: squad.id, member: ann, to: await newMember() }),
    ).rejects.toMatchObject({ reason: 'SQUAD_MEMBER_UNKNOWN' });
    const handed = await squads.handCaptaincy({ squad: squad.id, member: ann, to: cy });
    expect(handed.captain).toBe(cy);
    await expect(
      squads.handCaptaincy({ squad: squad.id, member: ann, to: bo }),
    ).rejects.toMatchObject({ reason: 'NOT_SQUAD_CAPTAIN' });
    expect((await settingsLog(squad.id)).at(-1)).toStrictEqual({
      actor_id: ann,
      kind: 'captainChanged',
      name: '早八跑团',
      captain_id: cy,
    });
  });

  it('lets the captain remove others, logged apart from leaving, and anyone remove themselves', async () => {
    const { squad, people } = await squadOf(3);
    const [ann, bo, cy] = [nth(people, 0), nth(people, 1), nth(people, 2)];
    await expect(
      squads.removeMember({ squad: squad.id, member: bo, removed: cy }),
    ).rejects.toMatchObject({ reason: 'NOT_SQUAD_CAPTAIN' });
    await squads.removeMember({ squad: squad.id, member: ann, removed: cy });
    await squads.removeMember({ squad: squad.id, member: ann, removed: cy });
    await squads.removeMember({ squad: squad.id, member: bo, removed: bo });
    expect(await squads.membersOf(squad.id)).toStrictEqual([ann]);
    const { rows } = await sql<{ member_id: string; kind: string; actor_id: string }>`
      select member_id, kind, actor_id from public.squad_membership_events
        where squad_id = ${squad.id} order by id
    `.execute(db);
    expect(rows.slice(3)).toStrictEqual([
      { member_id: cy, kind: 'removed', actor_id: ann },
      { member_id: bo, kind: 'left', actor_id: bo },
    ]);
  });

  it('passes to the earliest member left when the captain leaves', async () => {
    const { squad, people } = await squadOf(3);
    const [ann, bo] = [nth(people, 0), nth(people, 1)];
    await squads.leave({ squad: squad.id, member: ann });
    expect((await squads.find({ squad: squad.id, viewer: bo })).captain).toBe(bo);
    expect((await settingsLog(squad.id)).at(-1)).toStrictEqual({
      actor_id: ann,
      kind: 'captainChanged',
      name: '早八跑团',
      captain_id: bo,
    });
  });

  it('passes to the earliest member when the captain deletes their account', async () => {
    const { squad, people } = await squadOf(2);
    const [ann, bo] = [nth(people, 0), nth(people, 1)];
    await squads.rename({ squad: squad.id, member: ann, name: name('夜跑团') });
    await sql`delete from auth.users where id = ${ann}`.execute(db);
    expect((await squads.find({ squad: squad.id, viewer: bo })).captain).toBe(bo);
    await squads.rename({ squad: squad.id, member: bo, name: name('新队名') });
    // The log outlives the account, without saying who it was.
    expect(await settingsLog(squad.id)).toStrictEqual([
      { actor_id: null, kind: 'created', name: '早八跑团', captain_id: ann },
      { actor_id: null, kind: 'renamed', name: '夜跑团', captain_id: ann },
      { actor_id: bo, kind: 'renamed', name: '新队名', captain_id: bo },
    ]);
  });

  it('keeps the settings log append-only', async () => {
    const { squad } = await squadOf(1);
    await expect(
      sql`update public.squad_events set name = 'x' where squad_id = ${squad.id}`.execute(db),
    ).rejects.toMatchObject({ code: '42501' });
    await expect(
      sql`delete from public.squad_events where squad_id = ${squad.id}`.execute(db),
    ).rejects.toMatchObject({ code: '42501' });
  });
});

describe('the weekly goal', () => {
  const thisWeek = '2026-11-02';

  it('starts at 3 a member, or what the creator picked, from the week the squad is made', async () => {
    const ann = await newMember();
    const plain = await newSquad(ann, '默认');
    expect(await squads.weeklyGoal({ squad: plain.id, viewer: ann, week: thisWeek })).toStrictEqual(
      {
        daysPerMember: 3,
        nextDaysPerMember: 3,
      },
    );
    const bo = await newMember();
    const { squad: picked } = await squads.create({
      timeZone: NEW_YORK,
      week: thisWeek,
      id: SquadId.parse(randomUUID()),
      creator: bo,
      name: name('练得多'),
      daysPerMember: 5,
    });
    expect(await squads.weeklyGoal({ squad: picked.id, viewer: bo, week: thisWeek })).toStrictEqual(
      { daysPerMember: 5, nextDaysPerMember: 5 },
    );
    expect(await squads.daysPerMember(picked.id, thisWeek)).toBe(5);
    // Before the squad's first week, nobody set one: the default.
    expect(await squads.daysPerMember(picked.id, '2026-10-26')).toBe(3);
    expect(await squads.previewPublicInvite(picked.inviteCode)).toMatchObject({ daysPerMember: 5 });
  });

  it('lets only the captain change it, from next week, logged with who set it', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(ann);
    await squads.join({ inviteCode: squad.inviteCode, member: bo });
    await expect(
      squads.setWeeklyGoal({ squad: squad.id, member: bo, daysPerMember: 4, week: thisWeek }),
    ).rejects.toMatchObject({ reason: 'NOT_SQUAD_CAPTAIN' });
    expect(
      await squads.setWeeklyGoal({
        squad: squad.id,
        member: ann,
        daysPerMember: 4,
        week: thisWeek,
      }),
    ).toStrictEqual({ daysPerMember: 3, nextDaysPerMember: 4 });
    // The same again changes nothing; changing back is one more entry.
    await squads.setWeeklyGoal({ squad: squad.id, member: ann, daysPerMember: 4, week: thisWeek });
    expect(
      await squads.setWeeklyGoal({
        squad: squad.id,
        member: ann,
        daysPerMember: 3,
        week: thisWeek,
      }),
    ).toStrictEqual({ daysPerMember: 3, nextDaysPerMember: 3 });
    expect(await squads.daysPerMember(squad.id, '2026-11-16')).toBe(3);
    expect(
      (await squads.weeklyGoals(squad.id)).map(({ week, daysPerMember, by }) => ({
        week,
        daysPerMember,
        by,
      })),
    ).toStrictEqual([
      { week: thisWeek, daysPerMember: 3, by: ann },
      { week: '2026-11-09', daysPerMember: 4, by: ann },
      { week: '2026-11-09', daysPerMember: 3, by: ann },
    ]);
    expect(await squads.previewPublicInvite(squad.inviteCode)).toMatchObject({ daysPerMember: 3 });
  });

  it('keeps the goal log append-only', async () => {
    const ann = await newMember();
    const squad = await newSquad(ann);
    await expect(
      sql`update squad_weekly_goals set days_per_member = 7 where squad_id = ${squad.id}`.execute(
        db,
      ),
    ).rejects.toMatchObject({ code: '42501' });
    await expect(
      sql`delete from squad_weekly_goals where squad_id = ${squad.id}`.execute(db),
    ).rejects.toMatchObject({ code: '42501' });
  });
});

describe('a squad’s time zone', () => {
  const thisWeek = '2026-11-02';
  // Wednesday of that week everywhere.
  const during = new Date('2026-11-04T12:00:00Z');

  it('starts as the creator picked it, from the week the squad is made, else New York', async () => {
    const ann = await newMember();
    const plain = await newSquad(ann, '默认');
    expect(await squads.timeZone({ squad: plain.id, viewer: ann, moment: during })).toStrictEqual({
      timeZone: 'America/New_York',
      nextTimeZone: 'America/New_York',
    });
    const bo = await newMember();
    const { squad: taipei } = await squads.create({
      week: thisWeek,
      id: SquadId.parse(randomUUID()),
      creator: bo,
      name: name('台北队'),
      timeZone: 'Asia/Taipei',
    });
    expect(await squads.timeZone({ squad: taipei.id, viewer: bo, moment: during })).toStrictEqual({
      timeZone: 'Asia/Taipei',
      nextTimeZone: 'Asia/Taipei',
    });
    // Before the squad's first week it kept New York, as every squad did.
    expect(
      [taipei.id, plain.id].map(await squads.timeZonesFor([taipei.id, plain.id], '2026-10-26')),
    ).toStrictEqual(['America/New_York', 'America/New_York']);
    expect(
      [taipei.id].map(await squads.timeZonesAt([taipei.id], new Date('2026-11-04T12:00:00Z'))),
    ).toStrictEqual(['Asia/Taipei']);
  });

  it('keeps its zone from the moment it is made, when the creator’s week is ahead of it', async () => {
    // Made Monday 01:00 in Taipei (2026-11-08T17:00Z) on Los Angeles, where it is still Sunday.
    const made = new Date('2026-11-08T17:00:00Z');
    const cy = await newMember();
    const { squad } = await squads.create({
      week: '2026-11-09',
      timeZoneWeek: '2026-11-02',
      id: SquadId.parse(randomUUID()),
      creator: cy,
      name: name('洛杉矶队'),
      timeZone: 'America/Los_Angeles',
    });
    expect([squad.id].map(await squads.timeZonesAt([squad.id], made))).toStrictEqual([
      'America/Los_Angeles',
    ]);
    expect([squad.id].map(await squads.timeZonesFor([squad.id], '2026-11-09'))).toStrictEqual([
      'America/Los_Angeles',
    ]);
  });

  it('refuses a zone that doesn’t exist', async () => {
    const ann = await newMember();
    await expect(
      squads.create({
        week: thisWeek,
        id: SquadId.parse(randomUUID()),
        creator: ann,
        name: name('火星队'),
        timeZone: 'Mars/Olympus',
      }),
    ).rejects.toMatchObject({ reason: 'TIME_ZONE_UNKNOWN' });
    const squad = await newSquad(ann);
    await expect(
      squads.setTimeZone({
        squad: squad.id,
        member: ann,
        timeZone: 'Mars/Olympus',
        moment: during,
      }),
    ).rejects.toMatchObject({ reason: 'TIME_ZONE_UNKNOWN' });
  });

  it('lets only the captain change it, at once, logged with who set it', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(ann);
    await squads.join({ inviteCode: squad.inviteCode, member: bo });
    await expect(
      squads.setTimeZone({ squad: squad.id, member: bo, timeZone: 'Asia/Taipei', moment: during }),
    ).rejects.toMatchObject({ reason: 'NOT_SQUAD_CAPTAIN' });
    expect(
      await squads.setTimeZone({
        squad: squad.id,
        member: ann,
        timeZone: 'Asia/Taipei',
        moment: during,
      }),
    ).toStrictEqual({ timeZone: 'Asia/Taipei', nextTimeZone: 'Asia/Taipei' });
    expect([squad.id].map(await squads.timeZonesFor([squad.id], thisWeek))).toStrictEqual([
      'Asia/Taipei',
    ]);
    // The same again changes nothing.
    await squads.setTimeZone({
      squad: squad.id,
      member: ann,
      timeZone: 'Asia/Taipei',
      moment: during,
    });
    const rows = await sql<{ time_zone: string; week_start: string; set_by: string }>`
      select time_zone, week_start::text, set_by from squad_time_zones
      where squad_id = ${squad.id} order by id`.execute(db);
    expect(rows.rows).toStrictEqual([
      { time_zone: 'America/New_York', week_start: thisWeek, set_by: ann },
      { time_zone: 'Asia/Taipei', week_start: thisWeek, set_by: ann },
    ]);
    await expect(
      sql`update squad_time_zones set time_zone = 'UTC' where squad_id = ${squad.id}`.execute(db),
    ).rejects.toMatchObject({ code: '42501' });
  });

  it('sets a change that waited for next week again, so the new one stands', async () => {
    const ann = await newMember();
    const squad = await newSquad(ann);
    // A change from when changes waited for the next week.
    await sql`insert into squad_time_zones (squad_id, time_zone, week_start, set_by)
      values (${squad.id}, 'Asia/Taipei', '2026-11-09', ${ann})`.execute(db);
    expect(
      await squads.setTimeZone({
        squad: squad.id,
        member: ann,
        timeZone: 'America/Los_Angeles',
        moment: during,
      }),
    ).toStrictEqual({ timeZone: 'America/Los_Angeles', nextTimeZone: 'America/Los_Angeles' });
    expect([squad.id].map(await squads.timeZonesFor([squad.id], '2026-11-16'))).toStrictEqual([
      'America/Los_Angeles',
    ]);
  });

  it('counts a change from next week once this week’s 战报 froze on the old clock', async () => {
    const ann = await newMember();
    const { squad } = await squads.create({
      week: thisWeek,
      id: SquadId.parse(randomUUID()),
      creator: ann,
      name: name('台北队'),
      timeZone: 'Asia/Taipei',
    });
    // Sunday 2026-11-08 21:00 in Taipei, an hour after the week of 11-02 froze there, is 05:00 in
    // Los Angeles. Counting at once would reopen that 战报 until Los Angeles's 8pm, so the week
    // keeps Taipei and Los Angeles waits for the next: this week's zone and next week's differ.
    const moment = new Date('2026-11-08T13:00:00Z');
    const waiting = { timeZone: 'Asia/Taipei', nextTimeZone: 'America/Los_Angeles' };
    expect(
      await squads.setTimeZone({
        squad: squad.id,
        member: ann,
        timeZone: 'America/Los_Angeles',
        moment,
      }),
    ).toStrictEqual(waiting);
    expect(await squads.timeZone({ squad: squad.id, viewer: ann, moment })).toStrictEqual(waiting);
    expect([squad.id].map(await squads.timeZonesFor([squad.id], thisWeek))).toStrictEqual([
      'Asia/Taipei',
    ]);
    expect([squad.id].map(await squads.timeZonesFor([squad.id], '2026-11-09'))).toStrictEqual([
      'America/Los_Angeles',
    ]);
    // Monday 02:00 in Taipei, still Sunday in Los Angeles: the squad's next week hasn't begun on
    // its new clock, so it is still in the frozen week, on Taipei.
    const monday = new Date('2026-11-08T18:00:00Z');
    expect([squad.id].map(await squads.timeZonesAt([squad.id], monday))).toStrictEqual([
      'Asia/Taipei',
    ]);
  });

  it('counts a change from next week on the squad’s Monday, a day ahead of the new clock', async () => {
    const ann = await newMember();
    const { squad } = await squads.create({
      week: thisWeek,
      id: SquadId.parse(randomUUID()),
      creator: ann,
      name: name('台北队'),
      timeZone: 'Asia/Taipei',
    });
    // Monday 2026-11-09 02:00 in Taipei, still Sunday 11-08 in New York. The week of 11-02 froze
    // on Taipei's clock, so New York counts from 11-09, which hasn't begun on its clock yet.
    const moment = new Date('2026-11-08T18:00:00Z');
    expect(
      await squads.setTimeZone({
        squad: squad.id,
        member: ann,
        timeZone: 'America/New_York',
        moment,
      }),
    ).toStrictEqual({ timeZone: 'Asia/Taipei', nextTimeZone: 'America/New_York' });
    expect([squad.id].map(await squads.timeZonesFor([squad.id], '2026-11-02'))).toStrictEqual([
      'Asia/Taipei',
    ]);
    expect([squad.id].map(await squads.timeZonesFor([squad.id], '2026-11-09'))).toStrictEqual([
      'America/New_York',
    ]);
  });

  it('counts a change from next week once this week’s 战报 froze on the new clock', async () => {
    const ann = await newMember();
    const { squad } = await squads.create({
      week: thisWeek,
      id: SquadId.parse(randomUUID()),
      creator: ann,
      name: name('洛杉矶队'),
      timeZone: 'America/Los_Angeles',
    });
    // Sunday 2026-11-08 19:00 in Los Angeles is Monday 11:00 in Taipei, 15 hours after Taipei's
    // Sunday 8pm: counting at once would freeze the week the squad is still playing. So the week
    // of 11-02 keeps Los Angeles and freezes at its 8pm, and the squad, already in its next week
    // on Taipei's clock, shows Taipei.
    const moment = new Date('2026-11-09T03:00:00Z');
    expect(
      await squads.setTimeZone({ squad: squad.id, member: ann, timeZone: 'Asia/Taipei', moment }),
    ).toStrictEqual({ timeZone: 'Asia/Taipei', nextTimeZone: 'Asia/Taipei' });
    expect([squad.id].map(await squads.timeZonesFor([squad.id], thisWeek))).toStrictEqual([
      'America/Los_Angeles',
    ]);
    expect([squad.id].map(await squads.timeZonesFor([squad.id], '2026-11-09'))).toStrictEqual([
      'Asia/Taipei',
    ]);
    // Changed back before Los Angeles's 8pm, it counts at once again, this week and the next.
    const back = new Date('2026-11-09T03:30:00Z');
    expect(
      await squads.setTimeZone({
        squad: squad.id,
        member: ann,
        timeZone: 'America/Los_Angeles',
        moment: back,
      }),
    ).toStrictEqual({ timeZone: 'America/Los_Angeles', nextTimeZone: 'America/Los_Angeles' });
  });
});

describe('the squad’s language', () => {
  it('lets only the captain pick it, counting at once, logged with who set it', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(ann);
    await squads.join({ inviteCode: squad.inviteCode, member: bo });
    expect(await squads.languagesOf([squad.id])).toStrictEqual(new Map());
    await expect(
      squads.setLanguage({ squad: squad.id, member: bo, language: 'en' }),
    ).rejects.toMatchObject({ reason: 'NOT_SQUAD_CAPTAIN' });
    await squads.setLanguage({ squad: squad.id, member: ann, language: 'zh-Hant' });
    // The same again changes nothing.
    await squads.setLanguage({ squad: squad.id, member: ann, language: 'zh-Hant' });
    await squads.setLanguage({ squad: squad.id, member: ann, language: 'en' });
    expect(await squads.languagesOf([squad.id])).toStrictEqual(new Map([[squad.id, 'en']]));
    const rows = await sql<{ language: string; set_by: string }>`
      select language, set_by from squad_languages where squad_id = ${squad.id} order by id`.execute(
      db,
    );
    expect(rows.rows).toStrictEqual([
      { language: 'zh-Hant', set_by: ann },
      { language: 'en', set_by: ann },
    ]);
    await expect(
      sql`update squad_languages set language = 'zh-Hans' where squad_id = ${squad.id}`.execute(db),
    ).rejects.toMatchObject({ code: '42501' });
  });
});
