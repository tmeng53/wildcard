import { randomUUID } from 'node:crypto';

import {
  CheckInId,
  MemberId,
  SquadId,
  SquadNotJoinedError,
  Training,
  type CheckInRecord,
  type SquadPost,
  type SquadToday,
} from '@wildcard/check-ins';
import { Character } from '@wildcard/members';
import {
  apnsPayload,
  type PushNotification,
  type PushSettings,
  type TeammatePushRing,
} from '@wildcard/push';
import { describe, expect, it } from 'vitest';

import { createLog } from '../log.js';
import { APNS_BYTES } from './daily-progress-push.js';
import {
  notifyTeammates,
  teammateNotification,
  type TeammatePushDependencies,
} from './teammate-push.js';

// Who is told of a 训练 and how, without a database: the stores' own tests cover the claim.
const day = '2026-11-13';
const squad = SquadId.parse(randomUUID());
const newMember = () => MemberId.parse(randomUUID());
const [tracy, ann, bo] = [newMember(), newMember(), newMember()];
const checkIn = CheckInId.parse(randomUUID());

const run: CheckInRecord & { readonly kind: 'trained' } = {
  id: checkIn,
  member: tracy,
  day,
  postedDay: day,
  createdAt: new Date('2026-11-13T12:00:00Z'),
  audience: [squad],
  inFeed: true,
  kind: 'trained',
  training: Training.parse({ sport: 'tennis', minutes: 62 }),
};

const today: SquadToday = {
  members: [tracy, ann, bo].map((member) => ({
    member,
    day,
    training: 'notCheckedIn' as const,
    latestMeal: undefined,
    plannedRest: false,
    firstCheckInAt: undefined,
  })),
  trainedToday: 1,
  disclaimerToday: 0,
  restingToday: 0,
  everyoneTrained: false,
  myWeek: { from: '2026-11-09', to: '2026-11-15', days: [], trainedDays: 0, plannedDays: 3 },
  myLifetimeTrainedDays: 0,
  squadWeek: { trainedDays: 4, plannedDays: 9, daysPerMember: 3 },
};

const profile = {
  catchphrase: null,
  character: Character.parse({
    nickname: '翠西',
    look: { persona: 'deadpan', variants: { body: 'peach' }, colors: {} },
  }),
  jerseyNumber: null,
  joinedAt: new Date(0),
  equippedTitle: null,
  equippedTeamBadge: null,
};

/** The flow on fakes: what was posted, each member's switch and language, and what was sent. */
function world({
  record = run,
  sending = true,
  off = [],
  rings = () => 'ring',
  named = true,
  posts = [],
}: {
  readonly record?: CheckInRecord | 'deleted';
  readonly sending?: boolean;
  readonly off?: readonly string[];
  readonly rings?: (member: string) => TeammatePushRing | undefined;
  readonly named?: boolean;
  readonly posts?: readonly SquadPost[];
} = {}) {
  const sent: { readonly member: string; readonly notification: PushNotification }[] = [];
  const settings: PushSettings = { dailyProgress: true, coach: true };
  const deps: TeammatePushDependencies = {
    checkIns: {
      current: () => Promise.resolve(record === 'deleted' ? undefined : record),
      squadToday: () => Promise.resolve(today),
      listForSquad: () => Promise.resolve([...posts]),
    },
    members: {
      squadmates: () => Promise.resolve(new Map(named ? [[tracy, profile]] : [])),
      languages: () => Promise.resolve(new Map([[bo, 'en' as const]])),
    },
    sportNames: () =>
      Promise.resolve(new Map([['tennis', { zhHans: '网球', zhHant: '網球', en: 'Tennis' }]])),
    push: {
      teammateSettings: () => Promise.resolve({ version: 1, sending, dailyRings: 5 }),
      settingsOf: (member) =>
        Promise.resolve({ ...settings, dailyProgress: !off.includes(member) }),
      claimTeammate: ({ member }) => Promise.resolve(rings(member)),
      notifyMembers: ({ members, notification }) => {
        sent.push(...members.map((member) => ({ member, notification })));
        return Promise.resolve({ sent: members.length, gone: 0, off: 0, failures: [] });
      },
    },
    clock: () => new Date('2026-11-13T12:00:05Z'),
    log: createLog(() => undefined),
  };
  return { deps, sent };
}

const event = { checkIn, squads: [squad] };
const alerts = (sent: ReturnType<typeof world>['sent']) =>
  Object.fromEntries(sent.map(({ member, notification }) => [member, notification.alert]));

describe('a 训练 just posted', () => {
  it('is told to every squadmate but its author, each in their own language', async () => {
    const { deps, sent } = world();
    await notifyTeammates(deps, event);
    expect(alerts(sent)).toStrictEqual({
      [ann]: { key: 'push.teammate.trained.minutes', args: ['翠西', '网球', '62'] },
      [bo]: { key: 'push.teammate.trained.minutes', args: ['翠西', 'Tennis', '62'] },
    });
  });

  it('rings, opens the post, and carries the squad’s week for its long-press view', async () => {
    const { deps, sent } = world();
    await notifyTeammates(deps, event);
    expect(sent[0]?.notification).toStrictEqual({
      alert: { key: 'push.teammate.trained.minutes', args: ['翠西', '网球', '62'] },
      category: 'teammateCheckIn',
      thread: 'teammates',
      collapseId: `teammate-${checkIn}`,
      interruption: 'active',
      since: 2,
      event: {
        kind: 'teammateCheckIn',
        checkIn,
        squad,
        squadTrainedDays: 4,
        squadPlannedDays: 9,
        today: { members: [{ id: ann }], posts: [], more: 0 },
      },
    });
  });

  it('carries the post itself among today’s, for the long-press view to cheer', async () => {
    const { deps, sent } = world({ posts: [{ checkIn: run, reactions: [], comments: [] }] });
    await notifyTeammates(deps, event);
    expect(sent[0]?.notification.event).toMatchObject({
      today: { posts: [{ id: checkIn, minutes: 62 }], more: 0 },
    });
  });

  it('goes silently to a member whose rings are used up, and not at all once handled', async () => {
    const { deps, sent } = world({
      rings: (member) => (member === ann ? 'silent' : undefined),
    });
    await notifyTeammates(deps, event);
    expect(
      sent.map(({ member, notification }) => [member, notification.interruption]),
    ).toStrictEqual([[ann, 'passive']]);
  });

  it('names the member’s own sport, and leaves out minutes the post doesn’t have', async () => {
    const { deps, sent } = world({
      record: { ...run, training: Training.parse({ sport: 'custom', customSport: '飞盘' }) },
    });
    await notifyTeammates(deps, event);
    expect(alerts(sent)[ann]).toStrictEqual({
      key: 'push.teammate.trained',
      args: ['翠西', '飞盘'],
    });
  });

  it('skips a member who turned 通知 off', async () => {
    const { deps, sent } = world({ off: [ann] });
    await notifyTeammates(deps, event);
    expect(sent.map(({ member }) => member)).toStrictEqual([bo]);
  });

  const quiet: readonly (readonly [string, CheckInRecord | 'deleted'])[] = [
    ['a meal', { ...run, kind: 'healthyMeal', meal: {} }],
    ['a post kept off 动态', { ...run, inFeed: false }],
    ['a 补打卡 for an earlier day', { ...run, day: '2026-11-12' }],
    [
      'a 训练 a phone sent up over an hour after it was made',
      { ...run, createdAt: new Date('2026-11-13T10:59:00Z') },
    ],
    ['a post since deleted', 'deleted'],
  ];
  it.each(quiet)('says nothing of %s', async (_, record) => {
    const { deps, sent } = world({ record });
    await notifyTeammates(deps, event);
    expect(sent).toStrictEqual([]);
  });

  it('says nothing while it is switched off for everyone, or before the author has a name', async () => {
    const off = world({ sending: false });
    await notifyTeammates(off.deps, event);
    const nameless = world({ named: false });
    await notifyTeammates(nameless.deps, event);
    expect([off.sent, nameless.sent]).toStrictEqual([[], []]);
  });

  it('says nothing, without failing, once the author has left the squad', async () => {
    const { deps, sent } = world({});
    const left = {
      ...deps,
      checkIns: {
        ...deps.checkIns,
        squadToday: () => Promise.reject(new SquadNotJoinedError(squad)),
      },
    };
    await expect(notifyTeammates(left, event)).resolves.toBeUndefined();
    expect(sent).toStrictEqual([]);
  });

  it('throws when it can’t read the squad, so the event comes again', async () => {
    const { deps } = world({});
    const down = {
      ...deps,
      checkIns: { ...deps.checkIns, squadToday: () => Promise.reject(new Error('database down')) },
    };
    await expect(notifyTeammates(down, event)).rejects.toThrow('database down');
  });

  it('tells the others, then throws, when one member can’t be claimed, so the event comes again', async () => {
    const { deps, sent } = world({});
    const down = {
      ...deps,
      push: {
        ...deps.push,
        claimTeammate: ({ member }: { readonly member: string }) =>
          member === ann
            ? Promise.reject(new Error('database down'))
            : Promise.resolve('ring' as const),
      },
    };
    await expect(notifyTeammates(down, event)).rejects.toThrow('database down');
    expect(sent.map(({ member }) => member)).toStrictEqual([bo]);
  });

  it('doesn’t throw once a push is claimed, since it is never sent twice', async () => {
    const { deps } = world({});
    const down = {
      ...deps,
      push: { ...deps.push, notifyMembers: () => Promise.reject(new Error('APNs down')) },
    };
    await expect(notifyTeammates(down, event)).resolves.toBeUndefined();
  });

  it('fits APNs with the longest names', () => {
    const payload = apnsPayload(
      teammateNotification({
        checkIn,
        squad,
        nickname: '👨‍👩‍👧‍👦'.repeat(12),
        sport: '👨‍👩‍👧‍👦'.repeat(12),
        minutes: 600,
        ring: 'ring',
        squadWeek: { trainedDays: 56, plannedDays: 56 },
      }),
    );
    expect(Buffer.byteLength(JSON.stringify(payload))).toBeLessThan(APNS_BYTES / 2);
  });
});
