import { randomUUID } from 'node:crypto';

import {
  CheckInId,
  Emoji,
  MemberId,
  SquadId,
  type SquadPost,
  type SquadToday,
} from '@wildcard/check-ins';
import { Look, Nickname, type MemberId as ProfileMember, type Squadmate } from '@wildcard/members';
import { apnsPayload } from '@wildcard/push';
import { describe, expect, it } from 'vitest';

import { APNS_BYTES, dailyProgressNotification, roomForToday } from './daily-progress-push.js';
import { POKERS, POST_REACTIONS, TODAY_POSTS, pushToday } from './daily-push-today.js';

// The size of the push at its fullest, without a database: the most squad, names, words and
// reactions the rules allow.
const day = '2026-10-23';
const squad = SquadId.parse(randomUUID());
const viewer = MemberId.parse(randomUUID());
const mates = Array.from({ length: 7 }, () => MemberId.parse(randomUUID()));
const everyone = [viewer, ...mates];
// The widest emoji: a family, 7 code points and 25 bytes.
const family = Emoji.parse('👨‍👩‍👧‍👦');
// Every name, sport and caption at its longest, all in the widest emoji.
const nickname = Nickname.parse(family.repeat(12));
const look = Look.parse({ persona: 'deadpan', variants: { body: 'peach' }, colors: {} });

const today: SquadToday = {
  members: everyone.map((member) => ({
    member,
    day,
    training: 'trained',
    latestMeal: undefined,
    plannedRest: false,
    firstCheckInAt: new Date(),
  })),
  trainedToday: everyone.length,
  disclaimerToday: 0,
  restingToday: 0,
  everyoneTrained: true,
  myWeek: { from: '2026-10-19', to: '2026-10-25', days: [], trainedDays: 5, plannedDays: 5 },
  myLifetimeTrainedDays: 5,
  squadWeek: { trainedDays: 40, plannedDays: 40 },
};

function post(author: MemberId, minute: number): SquadPost {
  return {
    checkIn: {
      id: CheckInId.parse(randomUUID()),
      member: author,
      day,
      createdAt: new Date(Date.UTC(2026, 9, 23, 18, minute)),
      audience: [squad],
      kind: 'trained',
      training: {
        sport: 'custom',
        customSport: family.repeat(20),
        caption: family.repeat(60),
      },
    },
    reactions: everyone
      .filter((member) => member !== author)
      .map((member, at) => ({ member, emoji: family, reactedAt: new Date(at * 1000) })),
  };
}

const posts = mates.flatMap((mate, at) => [post(mate, at * 2), post(mate, at * 2 + 1)]);

// Every member named at the longest a name can be.
const everyoneNamed = {
  checkIns: { listForSquad: () => Promise.resolve(posts) },
  members: {
    squadmates: (members: readonly ProfileMember[]) =>
      Promise.resolve(
        new Map<ProfileMember, Squadmate>(
          members.map((member) => [member, { catchphrase: null, character: { nickname, look } }]),
        ),
      ),
  },
};

describe('the push’s today', () => {
  it('keeps the whole push under APNs’ 4KB at its fullest', async () => {
    const told = {
      day,
      squad,
      squadWeek: today.squadWeek,
      received: new Map([
        ['reaction', new Set<string>(mates)],
        ['poke', new Set<string>(mates)],
      ]),
      named: { kind: 'poke' as const, nickname },
    };
    // Every teammate patted the member: the view names three.
    const carried = await pushToday(everyoneNamed, {
      viewer,
      squad,
      today,
      pokers: mates,
      bytes: roomForToday(told),
    });
    const payload = apnsPayload(dailyProgressNotification({ ...told, today: carried }));
    expect(Buffer.byteLength(JSON.stringify(payload))).toBeLessThanOrEqual(APNS_BYTES);
    // Even at its fullest, all four fit; the rest are counted.
    expect(carried?.posts).toHaveLength(TODAY_POSTS);
    expect(carried?.more).toBe(posts.length - TODAY_POSTS);
    expect(carried?.pokedBy).toHaveLength(POKERS);
    // Cut by bytes, so they still say something.
    expect(carried?.posts[0]?.text).toMatch(/^(👨‍👩‍👧‍👦)+…$/u);
    expect(carried?.members[1]?.name).toMatch(/^(👨‍👩‍👧‍👦)+…$/u);
  });

  it('leaves room for an alert that names someone with a long name', async () => {
    // One letter with many combining marks: a single character to the nickname rule.
    const long = Nickname.parse(`a${'\u0301'.repeat(999)}`);
    const told = {
      day,
      squad,
      squadWeek: today.squadWeek,
      received: new Map([['poke', new Set<string>(mates)]]),
      named: { kind: 'poke' as const, nickname: long },
    };
    const carried = await pushToday(everyoneNamed, {
      viewer,
      squad,
      today,
      pokers: mates,
      bytes: roomForToday(told),
    });
    const payload = apnsPayload(dailyProgressNotification({ ...told, today: carried }));
    expect(Buffer.byteLength(JSON.stringify(payload))).toBeLessThanOrEqual(APNS_BYTES);
    // Fewer posts fit; the rest are counted.
    expect(carried?.posts.length).toBeLessThan(TODAY_POSTS);
    expect(carried?.more).toBe(posts.length - (carried?.posts.length ?? 0));
  });

  it('keeps the newest reactions and always the member’s own', async () => {
    // Reactors from another squad the post went to as well: more than the cap.
    const others = Array.from({ length: POST_REACTIONS + 2 }, () => MemberId.parse(randomUUID()));
    const [first] = posts;
    if (first === undefined) throw new Error('no post');
    const reacted: SquadPost = {
      ...first,
      reactions: [viewer, ...others].map((member, at) => ({
        member,
        emoji: family,
        // The member's own is the oldest.
        reactedAt: new Date(at * 1000),
      })),
    };
    const carried = await pushToday(
      {
        checkIns: { listForSquad: () => Promise.resolve([reacted]) },
        members: { squadmates: () => Promise.resolve(new Map<ProfileMember, Squadmate>()) },
      },
      { viewer, squad, today, pokers: [], bytes: APNS_BYTES },
    );
    const [shown] = carried?.posts ?? [];
    const who = shown?.reactions.map(([at]) => carried?.members[at]?.id);
    expect(who).toEqual([...others].reverse().slice(0, POST_REACTIONS).concat(viewer));
    expect(shown?.reactionCount).toBe(POST_REACTIONS + 3);
  });

  it('carries nothing when there is no room even without posts', async () => {
    const carried = await pushToday(everyoneNamed, { viewer, squad, today, pokers: [], bytes: 40 });
    expect(carried).toBeUndefined();
  });
});
