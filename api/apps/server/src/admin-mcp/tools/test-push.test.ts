import { randomUUID } from 'node:crypto';

import { AdminId } from '@wildcard/admins';
import { DeviceToken, MemberId as PushMember, type PushNotification } from '@wildcard/push';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';

import { createDatabase } from '../../adapters/postgres.js';
import { TestPushNoSquadError } from '../../errors.js';
import { config, pushOn, signUp } from '../../test-kit/local-supabase.js';
import { sendTestPush } from './test-push.js';

// The test push on local Supabase: squads and phones are real; the sender records what it
// would send to whom.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const squads = createSquads({
  store: createPostgresSquadStore(db),
  inviteCodes: randomInviteCodes,
  aiConsent: () => Promise.resolve(true),
});

// Saturday 2026-10-31 in New York; the latest awards are the week of 10-19's.
const NOW = new Date('2026-10-31T03:00:00.000Z');

/** A signed-up member with one phone. */
async function member() {
  const { userId } = await signUp();
  const token = DeviceToken.parse(randomUUID().replaceAll('-', '').repeat(2));
  await pushOn(db).registerDevice({
    member: PushMember.parse(userId),
    device: { token, environment: 'production' },
  });
  return { userId, token };
}

async function squadOf(...joined: readonly { readonly userId: string }[]) {
  const id = randomUUID();
  await sql`insert into public.squads (id, name, invite_code)
    values (${id}, 'squad', ${randomInviteCodes()})`.execute(db);
  for (const each of joined) {
    await sql`insert into public.squad_members (squad_id, member_id)
      values (${id}, ${each.userId})`.execute(db);
  }
  return id;
}

function setup(answer: 'sent' | 'off' = 'sent') {
  const sent: { token: string; notification: PushNotification }[] = [];
  const tool = sendTestPush({
    push: pushOn(db, {
      send: (device, notification) => {
        sent.push({ token: device.token, notification });
        return Promise.resolve(answer);
      },
    }),
    squads,
    clock: () => NOW,
  });
  return { tool, sent };
}

describe('send_test_push', () => {
  it('sends each kind to the admin’s own phones only, as the real push is built', async () => {
    const admin = await member();
    const teammate = await member();
    const squad = await squadOf(admin, teammate);
    const { tool, sent } = setup();
    const context = { admin: AdminId.parse(admin.userId) };

    for (const kind of ['dailyProgress', 'poke', 'weeklyAwards']) {
      expect(await tool.run({ kind }, context)).toStrictEqual({
        version: 1,
        kind,
        phones: 1,
        sent: 1,
        off: 0,
        gone: 0,
        failures: [],
      });
    }

    expect(sent.map(({ token }) => token)).toStrictEqual([admin.token, admin.token, admin.token]);
    expect(sent.map(({ notification }) => notification.alert)).toStrictEqual([
      { key: 'push.dailyProgress', args: ['3', '5'] },
      { key: 'push.dailyProgress.poke', args: ['3', '5', '测试队友'] },
      { key: 'push.weeklyAwards.ready' },
    ]);
    expect(sent.map(({ notification }) => notification.event.squad)).toStrictEqual([
      squad,
      squad,
      squad,
    ]);
    expect(sent[2]?.notification.event.weekStart).toBe('2026-10-19');
    // Never collapsing into the real push of the day or week on the phone.
    expect(sent.map(({ notification }) => notification.collapseId)).toStrictEqual([
      `test-dailyProgress-${String(NOW.getTime())}`,
      `test-poke-${String(NOW.getTime())}`,
      `test-weeklyAwards-${String(NOW.getTime())}`,
    ]);
  });

  it('says when the server has no APNs key, so nothing reached the phone', async () => {
    const admin = await member();
    await squadOf(admin);
    const { tool } = setup('off');

    expect(
      await tool.run({ kind: 'dailyProgress' }, { admin: AdminId.parse(admin.userId) }),
    ).toMatchObject({ phones: 1, sent: 0, off: 1 });
  });

  it('refuses an admin in no squad, since every push is about one', async () => {
    const admin = await member();
    const { tool, sent } = setup();

    await expect(
      tool.run({ kind: 'poke' }, { admin: AdminId.parse(admin.userId) }),
    ).rejects.toBeInstanceOf(TestPushNoSquadError);
    expect(sent).toStrictEqual([]);
  });

  it('takes only the kinds it knows', () => {
    const { tool } = setup();

    expect(() => tool.run({ kind: 'lightsOn' }, { admin: AdminId.parse(randomUUID()) })).toThrow();
  });
});
