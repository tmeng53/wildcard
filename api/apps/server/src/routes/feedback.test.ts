import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createFeedbackInbox, createPostgresFeedbackStore } from '@wildcard/feedback';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { randomUUID } from 'node:crypto';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { IssueTrackerUnavailableError } from '../errors.js';
import { FILE_AFTER_MS, fileWaitingFeedback } from '../flows/feedback-issues.js';
import { createLog } from '../log.js';
import { PhotoPath, type IssueTracker } from '../ports.js';
import {
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  placeRatingsOn,
  savedPlacesOn,
  pushOn,
  scenesOn,
  signUp,
  switchesOn,
  weatherOn,
} from '../test-kit/local-supabase.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import {
  ignoredNotices,
  unusedCoachActivity,
  unusedCoachHiring,
  unusedCoachLetters,
  unusedGifts,
  noRewards,
  unusedUnlocks,
  unusedWeeklyAwards,
} from '../test-kit/weekly-awards.js';

// The whole journey against local Supabase: upload a screenshot, send feedback, see it filed.
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
const app = {
  appVersion: '1.0',
  build: '180',
  os: 'iOS 26.1',
  device: 'iPhone17,3',
  language: 'zh-Hans',
};

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});

type Opened = Parameters<IssueTracker['open']>[0];

/** An issue tracker that keeps what it was asked to open, or refuses while `down`. */
function trackerKeeping() {
  const opened: Opened[] = [];
  let down = false;
  const tracker: IssueTracker = {
    find: ({ marker }) => {
      if (down) return Promise.reject(new IssueTrackerUnavailableError('down'));
      const index = opened.findIndex((issue) => issue.body.includes(marker));
      return Promise.resolve(
        index === -1
          ? undefined
          : { number: index + 1, url: `https://github.com/o/r/issues/${String(index + 1)}` },
      );
    },
    open: (issue) => {
      if (down) return Promise.reject(new IssueTrackerUnavailableError('down'));
      opened.push(issue);
      return Promise.resolve({
        number: opened.length,
        url: `https://github.com/o/r/issues/${String(opened.length)}`,
      });
    },
  };
  return {
    tracker,
    opened,
    setDown: (value: boolean) => {
      down = value;
    },
  };
}

function appWith(issues: IssueTracker, clock: () => Date = () => new Date()) {
  const feedback = createFeedbackInbox({ store: createPostgresFeedbackStore(db), clock });
  const sports = createSports({ store: createPostgresSportStore(db) });
  const squads = createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: () => Promise.resolve(true),
  });
  const server = createApp({
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
    checkIns: createCheckIns({
      sports,
      store: createPostgresCheckInStore(db),
      membership: squads,
      reactions: createPostgresReactionStore(db),
      comments: createPostgresCommentStore(db),
      plans: createPostgresWeeklyPlanStore(db),
      photos,
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
    weeklyPlans: createWeeklyPlans({
      sports,
      store: createPostgresWeeklyPlanStore(db),
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    members: createMembers({ store: createPostgresProfileStore(db) }),
    push: pushOn(db),
    squads,
    scenes: scenesOn(db),
    switches: switchesOn(db),
    weeklyAwards: unusedWeeklyAwards,
    unlocks: unusedUnlocks,
    gifts: unusedGifts,
    rewards: noRewards,
    coachHiring: unusedCoachHiring,
    coachActivity: unusedCoachActivity,
    coachLetters: unusedCoachLetters,
    ...ignoredNotices,
    feedback,
    issues,
    weather: weatherOn(db),
    aiConsent: aiConsentOn(db),
    nudges: nudgesOn(db),
    placeRatings: placeRatingsOn(db),
    savedPlaces: savedPlacesOn(db),
    log: createLog(() => undefined),
    jobs: noJobs,
    admin: adminOn(),
  });
  return { server, feedback };
}

/** Uploads a screenshot to the member's folder the way the app does, and answers its path. */
async function uploadScreenshot(member: string) {
  const path = PhotoPath.parse(`${member}/${randomUUID()}`);
  const uploaded = await fetch(await photos.createUploadUrl(path), {
    method: 'PUT',
    headers: { 'content-type': 'image/jpeg' },
    body: JPEG,
  });
  expect(uploaded.ok).toBe(true);
  return path;
}

async function send({
  server,
  token,
  body,
}: {
  readonly server: ReturnType<typeof appWith>['server'];
  readonly token: string;
  readonly body: Record<string, unknown>;
}) {
  const response = await server.request('/feedback', {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ version: 1, kind: 'problem', screenshots: [], app, ...body }),
  });
  return {
    status: response.status,
    body: z.record(z.string(), z.unknown()).parse(await response.json()),
  };
}

describe('POST /feedback', () => {
  it('saves a member’s message and files it as an issue with its screenshot, once', async () => {
    const { token, userId } = await signUp();
    const keeping = trackerKeeping();
    const { server } = appWith(keeping.tracker);
    const shot = await uploadScreenshot(userId);
    const id = randomUUID();
    const draft = { id, body: 'The photo keeps spinning.', screenshots: [shot] };

    expect(await send({ server, token, body: draft })).toStrictEqual({
      status: 201,
      body: { version: 1, id },
    });
    expect(await send({ server, token, body: draft })).toStrictEqual({
      status: 200,
      body: { version: 1, id },
    });
    expect(keeping.opened).toHaveLength(1);
    const [issue] = keeping.opened;
    expect(issue?.title).toBe('Problem: The photo keeps spinning. (iPhone17,3, iOS 26.1)');
    expect(issue?.labels).toStrictEqual(['app-feedback', 'new', 'bug', 'screenshot']);
    expect(issue?.folder).toBe(`feedback/app-${id}`);
    expect(issue?.attachments.map(({ name, bytes }) => [name, [...bytes]])).toStrictEqual([
      ['screenshot-1.jpg', [...JPEG]],
    ]);
    expect(issue?.body).toContain(`<!-- app-feedback:${id} -->`);
    expect(issue?.body).toContain('> The photo keeps spinning.');
    expect(issue?.body).toContain('{{attachment:screenshot-1.jpg}}');
    expect(issue?.body).toContain(`| Member | \`${userId}\` |`);
    expect(issue?.body).toContain('| App | 1.0 (180) |');
    const filed = await db
      .selectFrom('feedback_issues')
      .select('number')
      .where('feedback_id', '=', id)
      .execute();
    expect(filed).toStrictEqual([{ number: 1 }]);
  });

  it('refuses a screenshot not uploaded, or in someone else’s folder', async () => {
    const [ann, bo] = [await signUp(), await signUp()];
    const { server } = appWith(trackerKeeping().tracker);
    const missing = `${ann.userId}/${randomUUID()}`;
    expect(
      (
        await send({
          server,
          token: ann.token,
          body: { id: randomUUID(), body: 'Hi', screenshots: [missing] },
        })
      ).body,
    ).toMatchObject({ reason: 'PHOTO_NOT_UPLOADED' });
    const bos = await uploadScreenshot(bo.userId);
    const theirs = await send({
      server,
      token: ann.token,
      body: {
        id: randomUUID(),
        body: 'Hi',
        screenshots: [bos],
      },
    });
    expect([theirs.status, theirs.body.reason]).toStrictEqual([403, 'PHOTO_NOT_YOURS']);
    const empty = await send({ server, token: ann.token, body: { id: randomUUID(), body: '  ' } });
    expect([empty.status, empty.body.reason]).toStrictEqual([400, 'REQUEST_INVALID']);
  });

  it('keeps a message the tracker refused, and the job files it later', async () => {
    const { token } = await signUp();
    const keeping = trackerKeeping();
    keeping.setDown(true);
    let now = new Date('2099-02-01T00:00:00.000Z');
    const { server, feedback } = appWith(keeping.tracker, () => now);
    const id = randomUUID();
    expect(
      (await send({ server, token, body: { id, kind: 'idea', body: 'Dark mode?' } })).status,
    ).toBe(201);
    expect(keeping.opened).toHaveLength(0);

    keeping.setDown(false);
    now = new Date(now.getTime() + FILE_AFTER_MS + 1000);
    const deps = { feedback, issues: keeping.tracker, photos, log: createLog(() => undefined) };
    // Other tests' messages may wait ahead of it: the job files a few a run, oldest first.
    for (let run = 0; run < 10; run += 1) {
      if ((await fileWaitingFeedback(deps)).waiting === 0) break;
    }
    const mine = keeping.opened.filter((issue) => issue.folder === `feedback/app-${id}`);
    expect(mine.map((issue) => issue.labels)).toStrictEqual([['app-feedback', 'new', 'idea']]);
    await fileWaitingFeedback(deps);
    expect(keeping.opened.filter((issue) => issue.folder === `feedback/app-${id}`)).toHaveLength(1);
  });
  it('keeps the issue a try opened but couldn’t remember, and opens no other', async () => {
    const { token } = await signUp();
    const keeping = trackerKeeping();
    keeping.setDown(true);
    let now = new Date('2099-03-01T00:00:00.000Z');
    const { server, feedback } = appWith(keeping.tracker, () => now);
    const id = randomUUID();
    await send({ server, token, body: { id, kind: 'problem', body: 'It froze' } });
    keeping.setDown(false);
    now = new Date(now.getTime() + FILE_AFTER_MS + 1000);
    let forget = true;
    const forgetful = {
      toFile: (...args: Parameters<typeof feedback.toFile>) => feedback.toFile(...args),
      filed: (...args: Parameters<typeof feedback.filed>) => {
        if (!forget) return feedback.filed(...args);
        forget = false;
        return Promise.reject(new Error('database went away'));
      },
    };
    const log = createLog(() => undefined);
    const mine = () => keeping.opened.filter((issue) => issue.folder === `feedback/app-${id}`);
    for (let run = 0; run < 10 && mine().length === 0; run += 1) {
      await fileWaitingFeedback({ feedback: forgetful, issues: keeping.tracker, photos, log });
    }
    for (let run = 0; run < 10; run += 1) {
      const { waiting } = await fileWaitingFeedback({
        feedback: forgetful,
        issues: keeping.tracker,
        photos,
        log,
      });
      if (waiting === 0) break;
    }
    expect(mine()).toHaveLength(1);
    expect(await feedback.toFile(0, 1000)).not.toContainEqual(expect.objectContaining({ id }));
  });
});
