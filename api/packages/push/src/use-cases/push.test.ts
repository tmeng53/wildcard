import { randomBytes, randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresDailyPushStore } from '../adapters/postgres-daily-push-store.js';
import { createPostgresDeviceStore, type PushTables } from '../adapters/postgres-device-store.js';
import { createPostgresSettingsStore } from '../adapters/postgres-settings-store.js';
import { DeviceToken, MemberId, type Device } from '../domain/device.js';
import type { PushNotification } from '../domain/notification.js';
import { PushRejectedError } from '../errors.js';
import type { PushSender, SendOutcome } from '../ports.js';
import { createPush } from './push.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<PushTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

/** A new member, as Supabase Auth would make one. */
async function newMember(): Promise<MemberId> {
  const id = randomUUID();
  await sql`insert into auth.users (id, email) values (${id}, ${`${id}@example.com`})`.execute(db);
  return MemberId.parse(id);
}

const newToken = () => DeviceToken.parse(randomBytes(32).toString('hex'));

const notification: PushNotification = {
  alert: { key: 'push.test' },
  category: 'test',
  thread: 'test',
  interruption: 'active',
  event: {},
};

/** A sender that answers each token as told (`sent` by default) and records what it got. */
function scriptedSender(answers: ReadonlyMap<string, SendOutcome | Error> = new Map()) {
  const got: Device[] = [];
  const sender: PushSender = {
    send(device) {
      got.push(device);
      const answer = answers.get(device.token) ?? 'sent';
      return answer instanceof Error ? Promise.reject(answer) : Promise.resolve(answer);
    },
  };
  return { sender, got };
}

const store = createPostgresDeviceStore(db);
const stores = {
  store,
  settings: createPostgresSettingsStore(db),
  daily: createPostgresDailyPushStore(db),
};

describe('push devices', () => {
  it('sends to every phone a member registered, and only theirs', async () => {
    const [tracy, friend] = [await newMember(), await newMember()];
    const [phone, ipad, friendsPhone] = [newToken(), newToken(), newToken()];
    const { sender, got } = scriptedSender();
    const push = createPush({ ...stores, sender });
    await push.registerDevice({
      member: tracy,
      device: { token: phone, environment: 'production' },
    });
    await push.registerDevice({ member: tracy, device: { token: ipad, environment: 'sandbox' } });
    await push.registerDevice({
      member: friend,
      device: { token: friendsPhone, environment: 'production' },
    });

    expect(await push.notifyMembers({ members: [tracy], notification })).toStrictEqual({
      sent: 2,
      gone: 0,
      off: 0,
      failures: [],
    });
    expect(new Set(got)).toStrictEqual(
      new Set([
        { token: phone, environment: 'production' },
        { token: ipad, environment: 'sandbox' },
      ]),
    );
  });

  it('keeps one row for a repeated registration, and moves a phone to whoever signs in on it', async () => {
    const [tracy, friend] = [await newMember(), await newMember()];
    const phone = newToken();
    const push = createPush({ ...stores, sender: scriptedSender().sender });
    await push.registerDevice({ member: tracy, device: { token: phone, environment: 'sandbox' } });
    await push.registerDevice({ member: tracy, device: { token: phone, environment: 'sandbox' } });
    await push.registerDevice({
      member: friend,
      device: { token: phone, environment: 'production' },
    });

    expect(await store.devicesOf([tracy])).toStrictEqual([]);
    expect(await store.devicesOf([friend])).toStrictEqual([
      { token: phone, environment: 'production' },
    ]);
  });

  it('takes a token in either case as the same phone', async () => {
    const tracy = await newMember();
    const hex = randomBytes(32).toString('hex');
    const push = createPush({ ...stores, sender: scriptedSender().sender });
    await push.registerDevice({
      member: tracy,
      device: { token: DeviceToken.parse(hex.toUpperCase()), environment: 'sandbox' },
    });
    await push.registerDevice({
      member: tracy,
      device: { token: DeviceToken.parse(hex), environment: 'sandbox' },
    });
    expect(await store.devicesOf([tracy])).toStrictEqual([{ token: hex, environment: 'sandbox' }]);
  });

  it('stops sending to a phone its member signed out on, and ignores anyone else asking', async () => {
    const [tracy, friend] = [await newMember(), await newMember()];
    const [phone, other] = [newToken(), newToken()];
    const push = createPush({ ...stores, sender: scriptedSender().sender });
    await push.registerDevice({ member: tracy, device: { token: phone, environment: 'sandbox' } });
    await push.registerDevice({ member: tracy, device: { token: other, environment: 'sandbox' } });

    await push.unregisterDevice({ member: friend, token: phone });
    await push.unregisterDevice({ member: tracy, token: other });
    await push.unregisterDevice({ member: tracy, token: other });
    expect(await store.devicesOf([tracy])).toStrictEqual([
      { token: phone, environment: 'sandbox' },
    ]);
  });

  it('forgets a dead token, and one failing phone doesn’t stop the others', async () => {
    const tracy = await newMember();
    const [dead, failing, fine] = [newToken(), newToken(), newToken()];
    const refused = new PushRejectedError(403, 'InvalidProviderToken');
    const { sender, got } = scriptedSender(
      new Map<string, SendOutcome | Error>([
        [dead, 'gone'],
        [failing, refused],
      ]),
    );
    const push = createPush({ ...stores, sender });
    for (const token of [dead, failing, fine]) {
      await push.registerDevice({ member: tracy, device: { token, environment: 'production' } });
    }

    expect(await push.notifyMembers({ members: [tracy], notification })).toStrictEqual({
      sent: 1,
      gone: 1,
      off: 0,
      failures: [refused],
    });
    expect(got).toHaveLength(3);
    expect(new Set(await store.devicesOf([tracy]))).toStrictEqual(
      new Set([
        { token: failing, environment: 'production' },
        { token: fine, environment: 'production' },
      ]),
    );
  });

  it('counts phones it didn’t send to while sending is off', async () => {
    const tracy = await newMember();
    const push = createPush({
      ...stores,
      sender: { send: () => Promise.resolve('off') },
    });
    await push.registerDevice({
      member: tracy,
      device: { token: newToken(), environment: 'sandbox' },
    });
    expect(await push.notifyMembers({ members: [tracy], notification })).toStrictEqual({
      sent: 0,
      gone: 0,
      off: 1,
      failures: [],
    });
  });

  it('sends nothing to no one', async () => {
    const { sender, got } = scriptedSender();
    const push = createPush({ ...stores, sender });
    expect(await push.notifyMembers({ members: [], notification })).toStrictEqual({
      sent: 0,
      gone: 0,
      off: 0,
      failures: [],
    });
    expect(got).toStrictEqual([]);
  });
});

describe('DeviceToken', () => {
  it.each([
    ['not hex', 'z'.repeat(64)],
    ['half a byte', 'a'.repeat(63)],
    ['too short', 'ab'.repeat(15)],
    ['empty', ''],
  ])('refuses a token that is %s', (_case, token) => {
    expect(DeviceToken.safeParse(token).success).toBe(false);
  });
});
