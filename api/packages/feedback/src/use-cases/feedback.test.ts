import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresFeedbackStore,
  type FeedbackTables,
} from '../adapters/postgres-feedback-store.js';
import { FeedbackId, MemberId } from '../domain/feedback.js';
import { FeedbackIdTakenError, FeedbackInvalidError, FeedbackLimitError } from '../errors.js';
import { createFeedbackInbox, FEEDBACK_DAILY_LIMIT } from './feedback.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<FeedbackTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
const members: MemberId[] = [];
// Deleting the members takes their messages, so no test leaves the filing queue a message.
afterAll(async () => {
  for (const id of members) await sql`delete from auth.users where id = ${id}`.execute(db);
  await db.destroy();
});

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  members.push(id);
  return id;
}

const app = {
  appVersion: '1.0',
  build: '180',
  os: 'iOS 26.1',
  device: 'iPhone17,3',
  language: 'zh-Hans',
};

function inboxAt(start: string) {
  let now = new Date(start);
  const inbox = createFeedbackInbox({ store: createPostgresFeedbackStore(db), clock: () => now });
  return {
    inbox,
    at: (time: string) => {
      now = new Date(time);
    },
  };
}

const message = (
  member: MemberId,
  { body = '  The photo keeps spinning.  ', screenshots = [`${member}/${randomUUID()}`] } = {},
) => ({
  id: FeedbackId.parse(randomUUID()),
  member,
  kind: 'problem' as const,
  body,
  source: { from: 'app' as const, screenshots, app },
});

describe('sending feedback', () => {
  it('saves the words trimmed, with the app it came from, once however often it is sent', async () => {
    const member = await newMember();
    const { inbox } = inboxAt('2026-11-08T04:00:00.000Z');
    const draft = message(member);
    const first = await inbox.send(draft);
    const again = await inbox.send(draft);
    expect([first.outcome, again.outcome, first.feedback.body]).toStrictEqual([
      'created',
      'unchanged',
      'The photo keeps spinning.',
    ]);
    const rows = await db
      .selectFrom('feedback')
      .select(['kind', 'body', 'screenshots', 'app'])
      .where('member_id', '=', member)
      .execute();
    expect(rows).toStrictEqual([
      {
        kind: 'problem',
        body: 'The photo keeps spinning.',
        screenshots: draft.source.screenshots,
        app: { version: 1, ...app },
      },
    ]);
  });

  it('refuses an empty message, a long one and a fourth screenshot', async () => {
    const member = await newMember();
    const { inbox } = inboxAt('2026-11-08T04:00:00.000Z');
    await expect(inbox.send(message(member, { body: '   ' }))).rejects.toBeInstanceOf(
      FeedbackInvalidError,
    );
    await expect(inbox.send(message(member, { body: '字'.repeat(1001) }))).rejects.toBeInstanceOf(
      FeedbackInvalidError,
    );
    await expect(
      inbox.send(message(member, { screenshots: ['a', 'b', 'c', 'd'] })),
    ).rejects.toBeInstanceOf(FeedbackInvalidError);
    await expect(inbox.send(message(member, { body: '字'.repeat(1000) }))).resolves.toMatchObject({
      outcome: 'created',
    }); // Emoji take up to 16 UTF-16 units each; the app counts each as one character.
    await expect(
      inbox.send(message(member, { body: '字'.repeat(990) + '👍🏽'.repeat(6) })),
    ).resolves.toMatchObject({ outcome: 'created' });
  });

  it('keeps what a coach passed on, with where and the member’s words, and files it like any', async () => {
    const member = await newMember();
    const { inbox, at } = inboxAt('2026-11-08T04:00:00.000Z');
    const [squad, checkIn, comment] = [randomUUID(), randomUUID(), randomUUID()];
    const relayed = {
      id: FeedbackId.parse(randomUUID()),
      member,
      kind: 'idea' as const,
      body: '想在动态上标地点',
      source: {
        from: 'coach' as const,
        coach: 'maotou',
        squad,
        checkIn,
        comment,
        quote: '@毛头 要是能 tag 地点就好了',
      },
    };
    await expect(inbox.send(relayed)).resolves.toMatchObject({ outcome: 'created' });
    const row = await db
      .selectFrom('feedback')
      .select(['screenshots', 'app', 'relayed'])
      .where('id', '=', relayed.id)
      .executeTakeFirstOrThrow();
    expect(row).toStrictEqual({
      screenshots: [],
      app: null,
      relayed: {
        version: 1,
        coach: 'maotou',
        squad,
        checkIn,
        comment,
        quote: '@毛头 要是能 tag 地点就好了',
      },
    });
    at('2026-11-08T05:00:00.000Z');
    const waiting = await inbox.toFile(0, 1000);
    expect(waiting.find(({ id }) => id === relayed.id)).toStrictEqual({
      ...relayed,
      at: new Date('2026-11-08T04:00:00.000Z'),
    });
    await expect(
      inbox.send({
        ...relayed,
        id: FeedbackId.parse(randomUUID()),
        source: { ...relayed.source, quote: ' ' },
      }),
    ).rejects.toBeInstanceOf(FeedbackInvalidError);
  });

  it('keeps a message from one place only', async () => {
    const member = await newMember();
    await expect(
      sql`insert into public.feedback (id, member_id, kind, body, app, relayed, at)
        values (${randomUUID()}, ${member}, 'idea', 'x', '{"version": 1}', '{"version": 1}', now())`.execute(
        db,
      ),
    ).rejects.toThrow(/feedback_one_source/);
  });

  it('takes 10 messages a day, still takes a retry, and more the next day', async () => {
    const member = await newMember();
    const { inbox, at } = inboxAt('2026-11-08T04:00:00.000Z');
    const first = message(member);
    await inbox.send(first);
    for (let n = 1; n < FEEDBACK_DAILY_LIMIT; n += 1) await inbox.send(message(member));
    await expect(inbox.send(message(member))).rejects.toBeInstanceOf(FeedbackLimitError);
    await expect(inbox.send(first)).resolves.toMatchObject({ outcome: 'unchanged' });
    at('2026-11-09T04:00:00.000Z');
    await expect(inbox.send(message(member))).resolves.toMatchObject({ outcome: 'created' });
  });

  it('takes no more than 10 from a burst sent at once', async () => {
    const member = await newMember();
    const { inbox } = inboxAt('2026-11-08T04:00:00.000Z');
    const tries = await Promise.allSettled(
      Array.from({ length: FEEDBACK_DAILY_LIMIT + 2 }, () => inbox.send(message(member))),
    );
    const created = tries.filter((t) => t.status === 'fulfilled');
    const refused = tries.filter(
      (t) => t.status === 'rejected' && t.reason instanceof FeedbackLimitError,
    );
    expect(created).toHaveLength(FEEDBACK_DAILY_LIMIT);
    expect(refused).toHaveLength(2);
  });

  it('refuses another member’s id', async () => {
    const [ann, bo] = [await newMember(), await newMember()];
    const { inbox } = inboxAt('2026-11-08T04:00:00.000Z');
    const draft = message(ann);
    await inbox.send(draft);
    await expect(inbox.send({ ...draft, member: bo })).rejects.toBeInstanceOf(FeedbackIdTakenError);
  });
});

describe('filing feedback', () => {
  it('lists messages old enough and not yet filed, oldest first, until each is filed', async () => {
    const member = await newMember();
    const { inbox, at } = inboxAt('2099-01-01T00:00:00.000Z');
    const first = message(member);
    const second = message(member);
    await inbox.send(first);
    at('2099-01-01T00:05:00.000Z');
    await inbox.send(second);
    at('2099-01-01T00:12:00.000Z');
    const mine = async () =>
      (await inbox.toFile(10 * 60 * 1000, 1000))
        .filter((f) => f.member === member)
        .map((f) => f.id);
    expect(await mine()).toStrictEqual([first.id]);
    at('2099-01-01T00:20:00.000Z');
    expect(await mine()).toStrictEqual([first.id, second.id]);
    await inbox.filed(first.id, { number: 12, url: 'https://github.com/o/r/issues/12' });
    await inbox.filed(first.id, { number: 13, url: 'https://github.com/o/r/issues/13' });
    expect(await mine()).toStrictEqual([second.id]);
    const issues = await db
      .selectFrom('feedback_issues')
      .select('number')
      .where('feedback_id', '=', first.id)
      .execute();
    expect(issues).toStrictEqual([{ number: 12 }]);
  });
});
