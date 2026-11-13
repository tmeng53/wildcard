import { randomBytes, randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresDailyPushStore } from '../adapters/postgres-daily-push-store.js';
import { createPostgresDailyPushSettings } from '../adapters/postgres-daily-push-settings.js';
import { createPostgresDeviceStore, type PushTables } from '../adapters/postgres-device-store.js';
import { createPostgresSettingsStore } from '../adapters/postgres-settings-store.js';
import {
  createPostgresTeammatePushSettings,
  createPostgresTeammatePushStore,
} from '../adapters/postgres-teammate-push.js';
import {
  DeviceToken,
  FIRST_PUSH_GENERATION as first,
  MemberId,
  PushGeneration,
  type Device,
} from '../domain/device.js';
import type { PushNotification } from '../domain/notification.js';
import { PushRejectedError } from '../errors.js';
import type { PushSender, SendOutcome } from '../ports.js';
import { createPush } from './push.js';
import { createTeammatePushSettings } from './teammate-push-settings.js';

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
  dailySettings: createPostgresDailyPushSettings(db),
  teammate: createPostgresTeammatePushStore(db),
  teammateSettings: createPostgresTeammatePushSettings(db),
};

describe('push devices', () => {
  it('sends to every phone a member registered, and only theirs', async () => {
    const [tracy, friend] = [await newMember(), await newMember()];
    const [phone, ipad, friendsPhone] = [newToken(), newToken(), newToken()];
    const { sender, got } = scriptedSender();
    const push = createPush({ ...stores, sender });
    await push.registerDevice({
      member: tracy,
      device: { token: phone, environment: 'production', generation: first },
    });
    await push.registerDevice({
      member: tracy,
      device: { token: ipad, environment: 'sandbox', generation: first },
    });
    await push.registerDevice({
      member: friend,
      device: { token: friendsPhone, environment: 'production', generation: first },
    });

    expect(await push.notifyMembers({ members: [tracy], notification })).toStrictEqual({
      sent: 2,
      gone: 0,
      off: 0,
      failures: [],
    });
    expect(new Set(got)).toStrictEqual(
      new Set([
        { token: phone, environment: 'production', generation: first },
        { token: ipad, environment: 'sandbox', generation: first },
      ]),
    );
  });

  it('keeps one row for a repeated registration, and moves a phone to whoever signs in on it', async () => {
    const [tracy, friend] = [await newMember(), await newMember()];
    const phone = newToken();
    const push = createPush({ ...stores, sender: scriptedSender().sender });
    await push.registerDevice({
      member: tracy,
      device: { token: phone, environment: 'sandbox', generation: first },
    });
    await push.registerDevice({
      member: tracy,
      device: { token: phone, environment: 'sandbox', generation: first },
    });
    await push.registerDevice({
      member: friend,
      device: { token: phone, environment: 'production', generation: first },
    });

    expect(await store.devicesOf([tracy])).toStrictEqual([]);
    expect(await store.devicesOf([friend])).toStrictEqual([
      { token: phone, environment: 'production', generation: first },
    ]);
  });

  it('takes a token in either case as the same phone', async () => {
    const tracy = await newMember();
    const hex = randomBytes(32).toString('hex');
    const push = createPush({ ...stores, sender: scriptedSender().sender });
    await push.registerDevice({
      member: tracy,
      device: {
        token: DeviceToken.parse(hex.toUpperCase()),
        environment: 'sandbox',
        generation: first,
      },
    });
    await push.registerDevice({
      member: tracy,
      device: { token: DeviceToken.parse(hex), environment: 'sandbox', generation: first },
    });
    expect(await store.devicesOf([tracy])).toStrictEqual([
      { token: hex, environment: 'sandbox', generation: first },
    ]);
  });

  it('stops sending to a phone its member signed out on, and ignores anyone else asking', async () => {
    const [tracy, friend] = [await newMember(), await newMember()];
    const [phone, other] = [newToken(), newToken()];
    const push = createPush({ ...stores, sender: scriptedSender().sender });
    await push.registerDevice({
      member: tracy,
      device: { token: phone, environment: 'sandbox', generation: first },
    });
    await push.registerDevice({
      member: tracy,
      device: { token: other, environment: 'sandbox', generation: first },
    });

    await push.unregisterDevice({ member: friend, token: phone });
    await push.unregisterDevice({ member: tracy, token: other });
    await push.unregisterDevice({ member: tracy, token: other });
    expect(await store.devicesOf([tracy])).toStrictEqual([
      { token: phone, environment: 'sandbox', generation: first },
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
      await push.registerDevice({
        member: tracy,
        device: { token, environment: 'production', generation: first },
      });
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
        { token: failing, environment: 'production', generation: first },
        { token: fine, environment: 'production', generation: first },
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
      device: { token: newToken(), environment: 'sandbox', generation: first },
    });
    expect(await push.notifyMembers({ members: [tracy], notification })).toStrictEqual({
      sent: 0,
      gone: 0,
      off: 1,
      failures: [],
    });
  });

  it('skips a phone whose build is from before the push’s words', async () => {
    const tracy = await newMember();
    const [older, newer] = [newToken(), newToken()];
    const { sender, got } = scriptedSender();
    const push = createPush({ ...stores, sender });
    await push.registerDevice({
      member: tracy,
      device: { token: older, environment: 'production', generation: first },
    });
    await push.registerDevice({
      member: tracy,
      device: { token: newer, environment: 'production', generation: PushGeneration.parse(2) },
    });

    expect(
      await push.notifyMembers({ members: [tracy], notification: { ...notification, since: 2 } }),
    ).toStrictEqual({ sent: 1, gone: 0, off: 0, failures: [] });
    expect(got.map(({ token }) => token)).toStrictEqual([newer]);
  });

  it('keeps the generation a phone last registered with', async () => {
    const tracy = await newMember();
    const phone = newToken();
    const push = createPush({ ...stores, sender: scriptedSender().sender });
    const device = { token: phone, environment: 'production' as const };
    await push.registerDevice({ member: tracy, device: { ...device, generation: first } });
    await push.registerDevice({
      member: tracy,
      device: { ...device, generation: PushGeneration.parse(2) },
    });
    expect(await store.devicesOf([tracy])).toStrictEqual([{ ...device, generation: 2 }]);
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

describe('push settings', () => {
  it('logs each switch flipped, in order, and never a save that changed nothing', async () => {
    const member = await newMember();
    // Saving the default before any switch was flipped changes nothing, so stores nothing.
    await stores.settings.save(member, { dailyProgress: true, coach: true });
    expect(await stores.settings.changedBy(member)).toStrictEqual(new Map());
    await stores.settings.save(member, { dailyProgress: false, coach: true });
    await stores.settings.save(member, { dailyProgress: false, coach: true });
    await stores.settings.save(member, { dailyProgress: true, coach: true });
    const { rows } = await sql<{ topic: string; enabled: boolean }>`
      select topic, enabled from push_setting_events where member_id = ${member} order by id
    `.execute(db);
    expect(rows).toStrictEqual([
      { topic: 'dailyProgress', enabled: false },
      { topic: 'dailyProgress', enabled: true },
    ]);
    expect(await stores.settings.changedBy(member)).toStrictEqual(
      new Map([['dailyProgress', true]]),
    );
  });

  it('changes only the switches a save names, so an older app keeps the coach’s', async () => {
    const member = await newMember();
    const push = createPush({ ...stores, sender: scriptedSender().sender });
    expect(await push.saveSettings({ member, settings: { coach: false } })).toStrictEqual({
      dailyProgress: true,
      coach: false,
    });
    expect(await push.saveSettings({ member, settings: { dailyProgress: false } })).toStrictEqual({
      dailyProgress: false,
      coach: false,
    });
    expect(await push.settingsOf(member)).toStrictEqual({ dailyProgress: false, coach: false });
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

describe('teammate pushes', () => {
  const push = createPush({ ...stores, sender: scriptedSender().sender });
  const at = (minute: number) => new Date(Date.UTC(2026, 10, 13, 12, minute));

  it('rings for the first few in 24 hours, then goes silently, and rings again a day later', async () => {
    const tracy = await newMember();
    const claim = (moment: Date) =>
      push.claimTeammate({ checkIn: randomUUID(), member: tracy, at: moment, dailyRings: 2 });

    expect([await claim(at(0)), await claim(at(1)), await claim(at(2))]).toStrictEqual([
      'ring',
      'ring',
      'silent',
    ]);
    // 24 hours after the first ring, one ring is free again; the silent one never counted.
    expect(await claim(new Date(at(0).getTime() + 24 * 60 * 60 * 1000))).toBe('ring');
    expect(await claim(new Date(at(0).getTime() + 24 * 60 * 60 * 1000 + 1))).toBe('silent');
  });

  it('handles a check-in once a member, and each member on their own count', async () => {
    const [tracy, friend] = [await newMember(), await newMember()];
    const checkIn = randomUUID();
    const told = { checkIn, at: at(0), dailyRings: 1 };

    expect(await push.claimTeammate({ ...told, member: tracy })).toBe('ring');
    expect(await push.claimTeammate({ ...told, member: tracy })).toBeUndefined();
    expect(await push.claimTeammate({ ...told, member: friend })).toBe('ring');
  });

  it('never rings when no rings are allowed', async () => {
    const tracy = await newMember();
    expect(
      await push.claimTeammate({ checkIn: randomUUID(), member: tracy, at: at(0), dailyRings: 0 }),
    ).toBe('silent');
  });

  it('logs a change of its settings once, with the whole new value', async () => {
    const admin = await newMember();
    // In a transaction rolled back after, so the settings every other test reads stay as seeded.
    const changed = { version: 1, sending: true, dailyRings: 3 };
    let seen: unknown;
    await db
      .transaction()
      .execute(async (scope) => {
        const settings = createTeammatePushSettings({
          store: createPostgresTeammatePushSettings(scope),
        });
        const seeded = await settings.current();
        const first = await settings.change({ dailyRings: 3 }, admin);
        const again = await settings.change({ dailyRings: 3 }, admin);
        const { rows } = await sql<{ settings: unknown }>`
          select settings from public.teammate_push_setting_events where changed_by = ${admin}
        `.execute(scope);
        seen = { seeded, first, again, rows };
        throw new Error('roll back');
      })
      .catch(() => undefined);
    expect(seen).toStrictEqual({
      seeded: { version: 1, sending: true, dailyRings: 5 },
      first: changed,
      again: changed,
      rows: [{ settings: changed }],
    });
  });
});
