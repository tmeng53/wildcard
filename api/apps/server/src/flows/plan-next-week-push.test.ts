import { randomBytes } from 'node:crypto';

import { createMembers, createPostgresProfileStore, MemberId } from '@wildcard/members';
import {
  createNotices,
  createPostgresBroadcastStore,
  createPostgresNoticeStore,
  MemberId as NoticeMember,
} from '@wildcard/notices';
import {
  createPostgresDailyPushSettings,
  DeviceToken,
  MemberId as PushMember,
  type PushNotification,
  type PushSender,
} from '@wildcard/push';
import { afterAll, describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { createLog } from '../log.js';
import { config, pushOn, signUp } from '../test-kit/local-supabase.js';
import { sendPlanNextWeek } from './plan-next-week-push.js';

// 去安排下周 on local Supabase, from members' zones to what each phone is sent. Other tests'
// members share the database, so each test looks only at its own phones.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());

/** Sunday 2026-11-08, 9pm in New York; 6pm in Los Angeles; Monday 11am in Tokyo. */
const SUNDAY_EVENING = new Date('2026-11-09T02:00:00Z');
const SETTINGS = {
  version: 2,
  sending: true,
  hour: 18,
  planReminderSending: true,
  planReminderHour: 20,
  planReminderMinute: 30,
} as const;

const sentTo = new Map<string, PushNotification[]>();
const recorder: PushSender = {
  send(device, notification) {
    sentTo.set(device.token, [...(sentTo.get(device.token) ?? []), notification]);
    return Promise.resolve('sent');
  },
};
const members = createMembers({ store: createPostgresProfileStore(db) });
const push = pushOn(db, recorder);
const notices = createNotices({
  store: createPostgresNoticeStore(db),
  broadcasts: createPostgresBroadcastStore(db),
  clock: () => new Date(),
});
const run = (now: Date = SUNDAY_EVENING) =>
  sendPlanNextWeek({ members, push, notices, clock: () => now, log: createLog(() => undefined) });

/** A member living in `timeZone`, with a phone. */
async function member(timeZone: string) {
  const { userId } = await signUp();
  await members.saveProfile({
    member: MemberId.parse(userId),
    profile: { timeZone, catchphrase: null, character: null },
  });
  const phone = randomBytes(32).toString('hex');
  await push.registerDevice({
    member: PushMember.parse(userId),
    device: { token: DeviceToken.parse(phone), environment: 'production' },
  });
  return { userId, phone };
}

describe('the Sunday 去安排下周 push', () => {
  it('goes once to each member whose Sunday is past 8:30pm, asking about the week after it', async () => {
    const [newYork, losAngeles, tokyo] = [
      await member('America/New_York'),
      await member('America/Los_Angeles'),
      await member('Asia/Tokyo'),
    ];
    await run();
    expect(sentTo.get(newYork.phone)).toStrictEqual([
      {
        alert: { key: 'push.planNextWeek' },
        category: 'planNextWeek',
        thread: 'planNextWeek',
        collapseId: 'planNextWeek-2026-11-09',
        interruption: 'active',
        event: { kind: 'planNextWeek', week: '2026-11-09' },
      },
    ]);
    // Los Angeles is still before 8:30pm, and Tokyo's Sunday is over.
    expect(sentTo.get(losAngeles.phone)).toBeUndefined();
    expect(sentTo.get(tokyo.phone)).toBeUndefined();

    // A run repeated, or Los Angeles' own evening later on, never sends New York's again.
    await run();
    await run(new Date('2026-11-09T05:00:00Z'));
    expect(sentTo.get(newYork.phone)).toHaveLength(1);
    expect(sentTo.get(losAngeles.phone)).toHaveLength(1);
    expect(sentTo.get(tokyo.phone)).toBeUndefined();
  });

  it('is kept in the member’s 通知 with the week it asks about', async () => {
    const { userId } = await member('America/New_York');
    await run();
    const page = await notices.page({ member: NoticeMember.parse(userId), limit: 10 });
    expect(page.notices.map(({ kind, subject }) => ({ kind, subject }))).toStrictEqual([
      {
        kind: 'planNextWeek',
        subject: {
          version: 1,
          alert: { key: 'push.planNextWeek', args: [] },
          weekStart: '2026-11-09',
        },
      },
    ]);
  });

  it('skips a member who turned the daily push off', async () => {
    const quiet = await member('America/New_York');
    await push.saveSettings({
      member: PushMember.parse(quiet.userId),
      settings: { dailyProgress: false },
    });
    await run();
    expect(sentTo.get(quiet.phone)).toBeUndefined();
  });

  it('sends nothing while it is off for everyone, and goes at the time the settings name', async () => {
    const settings = createPostgresDailyPushSettings(db);
    const by = PushMember.parse((await signUp()).userId);
    const losAngeles = await member('America/Los_Angeles');
    try {
      await settings.save({ ...SETTINGS, planReminderSending: false, planReminderHour: 17 }, by);
      await run();
      expect(sentTo.get(losAngeles.phone)).toBeUndefined();

      // On at 5:45pm: Los Angeles' 6pm is past it.
      await settings.save({ ...SETTINGS, planReminderHour: 17, planReminderMinute: 45 }, by);
      await run();
      expect(sentTo.get(losAngeles.phone)).toHaveLength(1);
    } finally {
      await settings.save(SETTINGS, by);
    }
  });
});
