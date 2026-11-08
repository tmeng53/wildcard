// GET /me/notices's broadcasts (群发通知) over the real notices, unlocks and database.
import { randomInt, randomUUID } from 'node:crypto';

import {
  MemberId as CheckInMember,
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import {
  BroadcastId,
  BroadcastValue,
  MemberId as NoticeMember,
  createNotices,
  createPostgresBroadcastStore,
  createPostgresNoticeStore,
} from '@wildcard/notices';
import {
  MemberId as UnlockMember,
  createCoachGifts,
  createPostgresGiftStore,
  createPostgresUnlockStore,
  createUnlocks,
} from '@wildcard/unlocks';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import {
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  pushOn,
  scenesOn,
  switchesOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import {
  unusedWeeklyAwards,
  unusedWeekSummaryWords,
  unusedCoachHiring,
  unusedCoachActivity,
  unusedCoachLetters,
  ignoredNotices,
  unusedFeedback,
} from '../test-kit/weekly-awards.js';

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const sports = createSports({ store: createPostgresSportStore(db) });
const checkIns = createCheckIns({
  sports,
  store: createPostgresCheckInStore(db),
  membership: createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: () => Promise.resolve(true),
  }),
  reactions: createPostgresReactionStore(db),
  comments: createPostgresCommentStore(db),
  plans: createPostgresWeeklyPlanStore(db),
  photos,
  calendarOf: () => Promise.resolve(undefined),
  clock: () => new Date(),
});
const unlocks = createUnlocks({
  store: createPostgresUnlockStore(db),
  trainedSince: ({ member, since }) =>
    checkIns.trainedSince({ member: CheckInMember.parse(member), since }),
  sportListed: (id) => sports.isListed(id),
  switches: () => Promise.resolve(() => true),
  switchListed: () => Promise.resolve(true),
});
// A year of this run's own, so broadcasts other runs left in the database never run with these.
const year = 2100 + randomInt(7800);
const notices = createNotices({
  store: createPostgresNoticeStore(db),
  broadcasts: createPostgresBroadcastStore(db),
  clock: () => new Date(`${String(year)}-11-21T12:00:00Z`),
  // As main.ts gives them: quietly, from the admin who saved the broadcast.
  giveGifts: async (member, broadcast) => {
    await unlocks.give(
      { member: UnlockMember.parse(member), items: broadcast.value.gifts },
      UnlockMember.parse(broadcast.by),
    );
    return true;
  },
});
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  accounts: createSupabaseAccounts({
    supabaseUrl: config.supabaseUrl,
    secretKey: config.supabaseSecretKey,
  }),
  revokeAppleSignIn: undefined,
  catalog: catalogOn(db),
  publicRoutes: unlimitedPublicRoutes,
  photos,
  checkIns,
  disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
  weeklyPlans: createWeeklyPlans({
    sports: createSports({ store: createPostgresSportStore(db) }),
    store: createPostgresWeeklyPlanStore(db),
    calendarOf: () => Promise.resolve(undefined),
    clock: () => new Date(),
  }),
  members: createMembers({ store: createPostgresProfileStore(db) }),
  push: pushOn(db),
  squads: createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: () => Promise.resolve(true),
  }),
  weeklyAwards: unusedWeeklyAwards,
  scenes: scenesOn(db),
  switches: switchesOn(db),
  unlocks,
  gifts: createCoachGifts({ store: createPostgresGiftStore(db) }),
  weekSummaryWords: unusedWeekSummaryWords,
  coachHiring: unusedCoachHiring,
  coachActivity: unusedCoachActivity,
  coachLetters: unusedCoachLetters,
  ...ignoredNotices,
  ...unusedFeedback,
  notices,
  aiConsent: aiConsentOn(db),
  nudges: nudgesOn(db),
  log: createLog(() => undefined),
  jobs: noJobs,
  admin: adminOn(),
});

async function get(path: string, token?: string) {
  const response = await app.request(path, {
    headers: token === undefined ? {} : { authorization: `Bearer ${token}` },
  });
  return { status: response.status, body: z.unknown().parse(await response.json()) };
}

describe('GET /me/notices: broadcasts', () => {
  it('tells a member a running broadcast once, in all three languages, with its gifts unlocked', async () => {
    const [me, admin] = [await signUp(), await signUp()];
    const words = (zhHans: string, en: string) => ({ zhHans, en, zhHant: zhHans });
    const id = BroadcastId.parse(`soon-${randomUUID().slice(0, 8)}`);
    const broadcast = BroadcastValue.parse({
      version: 1,
      title: words('商店街上新了', 'New in the stores'),
      body: words('快去看看吧！', 'Take a look!'),
      action: {
        label: words('去商店街看看', 'Take a look'),
        destination: 'stores',
      },
      style: 'banner',
      icon: { kind: 'store', id: 'deuce' },
      gifts: [{ kind: 'store', id: 'deuce' }],
      members: [me.userId],
      startsAt: `${String(year)}-11-20T00:00:00Z`,
      endsAt: `${String(year)}-11-27T00:00:00Z`,
    });
    await notices.put({ id, value: broadcast, by: NoticeMember.parse(admin.userId) });

    const first = await get('/me/notices', me.token);
    expect(first.status).toBe(200);
    const told = z
      .object({ notices: z.array(z.object({ kind: z.string() }).loose()) })
      .parse(first.body)
      .notices.filter(({ kind }) => kind === 'broadcast');
    expect(told).toMatchObject([
      {
        kind: 'broadcast',
        broadcast: id,
        title: broadcast.title,
        body: broadcast.body,
        action: broadcast.action,
        style: 'banner',
        icon: { kind: 'store', id: 'deuce' },
        gifts: [{ kind: 'store', id: 'deuce' }],
      },
    ]);
    // Whom it names stays with the admins.
    expect(told[0]).not.toHaveProperty('members');
    // Its gift is the member's, as if given with give_unlocks.
    expect((await get('/me/unlocks', me.token)).body).toMatchObject({
      unlocks: [{ kind: 'store', id: 'deuce' }],
    });

    // Told once.
    const again = z
      .object({ notices: z.array(z.object({ kind: z.string() }).loose()) })
      .parse((await get('/me/notices', me.token)).body)
      .notices.filter(({ kind }) => kind === 'broadcast');
    expect(again).toHaveLength(1);
  });
});

describe('GET /me/notices: goal suggestions', () => {
  it('reads a captain’s suggested goal with how many weeks the squad was over', async () => {
    const captain = await signUp();
    await notices.tell([
      {
        member: NoticeMember.parse(captain.userId),
        kind: 'goalSuggestion',
        subject: { version: 1, weeks: 3, daysPerMember: 4 },
      },
    ]);
    const page = await get('/me/notices', captain.token);
    expect(page.status).toBe(200);
    expect(page.body).toMatchObject({
      notices: [{ kind: 'goalSuggestion', weeks: 3, daysPerMember: 4 }],
    });
  });
});
