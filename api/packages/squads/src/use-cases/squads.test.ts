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
    id: SquadId.parse(randomUUID()),
    creator,
    name: name(text),
  });
  return squad;
}

describe('creating a squad', () => {
  it('saves it with only a name and the creator as its one member', async () => {
    const creator = await newMember();
    const id = SquadId.parse(randomUUID());
    const { squad, created } = await squads.create({ id, creator, name: name(' 早八跑团 ') });
    expect(created).toBe(true);
    expect({ ...squad, inviteCode: undefined, createdAt: undefined }).toStrictEqual({
      id,
      name: '早八跑团',
      inviteCode: undefined,
      createdAt: undefined,
      createdBy: creator,
      members: [{ member: creator, joinedAt: squad.members[0]?.joinedAt }],
    });
    expect(squad.inviteCode).toMatch(/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$/);
  });

  it('answers a retry with the squad already made, and refuses another name or member', async () => {
    const creator = await newMember();
    const id = SquadId.parse(randomUUID());
    const first = await squads.create({ id, creator, name: name('早八跑团') });
    const retry = await squads.create({ id, creator, name: name('早八跑团') });
    expect([retry.created, retry.squad]).toStrictEqual([false, first.squad]);
    await expect(squads.create({ id, creator, name: name('夜跑团') })).rejects.toMatchObject({
      reason: 'SQUAD_ID_CONFLICT',
    });
    await expect(
      squads.create({ id, creator: await newMember(), name: name('早八跑团') }),
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
    const again = await squads.create({ id: squad.id, creator, name: squad.name });
    expect([again.created, again.squad]).toStrictEqual([false, squad]);
    await expect(newSquad(creator)).rejects.toMatchObject({ reason: 'AI_CONSENT_REQUIRED' });
  });

  it('refuses a fourth squad, and allows one again after leaving', async () => {
    const member = await newMember();
    const [first] = [await newSquad(member), await newSquad(member), await newSquad(member)];
    await expect(newSquad(member)).rejects.toMatchObject({ reason: 'SQUAD_LIMIT_REACHED' });
    await squads.leave({ squad: first.id, member });
    await expect(newSquad(member)).resolves.toMatchObject({ name: '早八跑团' });
  });

  it('never lets a member past 3 squads, however many creates arrive at once', async () => {
    const member = await newMember();
    const results = await Promise.allSettled(Array.from({ length: 6 }, () => newSquad(member)));
    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(3);
    expect(await squads.listMine(member)).toHaveLength(3);
  });
});

describe('joining by invite code', () => {
  it('adds the member after the others, typed in any case and with a dash', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(ann);
    const typed = `${squad.inviteCode.slice(0, 4).toLowerCase()}-${squad.inviteCode.slice(4)}`;
    const { squad: joined, joined: isNew } = await squads.join({
      inviteCode: InviteCode.parse(typed),
      member: bo,
    });
    expect([isNew, joined.members.map(({ member }) => member)]).toStrictEqual([true, [ann, bo]]);
    const again = await squads.join({ inviteCode: squad.inviteCode, member: bo });
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
    const again = await squads.join({ inviteCode: squad.inviteCode, member });
    expect(again.joined).toBe(false);
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

  it('refuses a member already in 3 squads', async () => {
    const member = await newMember();
    for (let i = 0; i < 3; i += 1) await newSquad(member);
    const other = await newSquad(await newMember());
    await expect(squads.join({ inviteCode: other.inviteCode, member })).rejects.toMatchObject({
      reason: 'SQUAD_LIMIT_REACHED',
    });
  });

  it('previews the squad without its members or id', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(ann, '周末网球');
    expect(await squads.previewInvite({ inviteCode: squad.inviteCode, viewer: bo })).toStrictEqual({
      name: '周末网球',
      memberCount: 1,
      full: false,
      joined: false,
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
      members: [ann, bo],
    });
    await expect(squads.previewPublicInvite(InviteCode.parse('ZZZZZZZZ'))).rejects.toMatchObject({
      reason: 'INVITE_CODE_UNKNOWN',
    });
  });
});

describe('leaving and listing', () => {
  it('lists my squads in the order I joined, and leaving takes one out', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const first = await newSquad(ann, '一');
    const second = await newSquad(bo, '二');
    await squads.join({ inviteCode: second.inviteCode, member: ann });
    expect((await squads.listMine(ann)).map((squad) => squad.name)).toStrictEqual(['一', '二']);
    await squads.leave({ squad: first.id, member: ann });
    await squads.leave({ squad: first.id, member: ann });
    expect((await squads.listMine(ann)).map((squad) => squad.name)).toStrictEqual(['二']);
  });

  it('keeps a record of each time a member left, with when they had joined', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const squad = await newSquad(bo);
    const stints = () =>
      sql<{
        joined: boolean;
        left: boolean;
      }>`select joined_at < left_at as joined, left_at <= now() as left
        from public.squad_leaves where squad_id = ${squad.id} and member_id = ${ann}
        order by left_at`.execute(db);
    await squads.join({ inviteCode: squad.inviteCode, member: ann });
    await squads.leave({ squad: squad.id, member: ann });
    // Leaving a squad you aren't in leaves no record.
    await squads.leave({ squad: squad.id, member: ann });
    await squads.join({ inviteCode: squad.inviteCode, member: ann });
    await squads.leave({ squad: squad.id, member: ann });
    expect((await stints()).rows).toStrictEqual([
      { joined: true, left: true },
      { joined: true, left: true },
    ]);
    expect(await squads.membersOf(squad.id)).toStrictEqual([bo]);
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

  it('keeps a squad whose last member leaves, since check-ins may point at it', async () => {
    const ann = await newMember();
    const squad = await newSquad(ann);
    await squads.leave({ squad: squad.id, member: ann });
    const rows = await sql`select 1 from public.squads where id = ${squad.id}`.execute(db);
    expect(rows.rows).toHaveLength(1);
  });
});
