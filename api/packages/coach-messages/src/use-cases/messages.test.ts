import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresMessageStore,
  type CoachMessageTables,
} from '../adapters/postgres-message-store.js';
import { CardPath, MemberId, MessageId, MessageValue, SquadId } from '../domain/message.js';
import { CoachMessageAnswerInvalidError, CoachMessageNotFoundError } from '../errors.js';
import { createCoachMessages } from './messages.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<CoachMessageTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

let now = new Date('2090-03-01T08:00:00Z');
const messages = createCoachMessages({
  store: createPostgresMessageStore(db),
  clock: () => now,
});

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

const words = (zhHans: string) => ({ zhHans, en: zhHans, zhHant: zhHans });

/**
 * Messages are every member's, so each test runs its own in a window no other test's runs in,
 * named for only its own members.
 */
function value({
  members,
  startsAt,
  endsAt,
}: {
  members: readonly string[];
  startsAt: string;
  endsAt: string;
}): MessageValue {
  return MessageValue.parse({
    version: 1,
    card: {
      line: words('周四去的 Equinox，打个分？'),
      stars: true,
      input: { placeholder: words('说说看') },
      buttons: [
        { id: 'done', label: words('好了'), tap: [{ close: true }] },
        {
          id: 'more',
          label: words('还有话说'),
          tap: [{ next: { line: words('还想说什么？'), input: {} } }],
        },
      ],
      thanks: words('收到，谢谢你。'),
    },
    members,
    startsAt,
    endsAt,
  });
}

describe('coach messages', () => {
  it('saves a change as a new row, and nothing for a save that changes nothing', async () => {
    const admin = await newMember();
    const id = MessageId.parse(`m-${randomUUID().slice(0, 8)}`);
    const first = value({
      members: [admin],
      startsAt: '2090-01-01T00:00:00Z',
      endsAt: '2090-01-02T00:00:00Z',
    });
    expect((await messages.put({ id, value: first, by: admin })).changed).toBe(true);
    expect((await messages.put({ id, value: first, by: admin })).changed).toBe(false);
    const changed = { ...first, endsAt: '2090-01-03T00:00:00Z' };
    const saved = await messages.put({ id, value: changed, by: admin });
    expect(saved.changed).toBe(true);
    expect(saved.message.value.endsAt).toBe('2090-01-03T00:00:00Z');
    const { count } = await db
      .selectFrom('coach_messages')
      .select((eb) => eb.fn.countAll<string>().as('count'))
      .where('message_id', '=', id)
      .executeTakeFirstOrThrow();
    expect(Number(count)).toBe(2);
    await expect(
      sql`update public.coach_messages set message = '{}' where message_id = ${id}`.execute(db),
    ).rejects.toThrow();
  });

  it('gives a running message once, in the squad the member read it in, from its coach', async () => {
    const [me, other] = [await newMember(), await newMember()];
    const [squad, nextSquad] = [SquadId.parse(randomUUID()), SquadId.parse(randomUUID())];
    const id = MessageId.parse(`m-${randomUUID().slice(0, 8)}`);
    await messages.put({
      id,
      value: value({
        members: [me],
        startsAt: '2090-03-01T00:00:00Z',
        endsAt: '2090-03-02T00:00:00Z',
      }),
      by: me,
    });

    // No coach: a message is said by a coach, so none is given yet.
    expect(await messages.cardsFor({ member: me, squad, coach: undefined })).toStrictEqual([]);
    const cards = await messages.cardsFor({ member: me, squad, coach: 'maotou' });
    expect(cards.map((card) => [card.id, card.coach, card.at.toISOString()])).toStrictEqual([
      [id, 'maotou', '2090-03-01T08:00:00.000Z'],
    ]);
    // A later read, a new coach: the card keeps who said it and when.
    now = new Date('2090-03-01T09:00:00Z');
    const again = await messages.cardsFor({ member: me, squad, coach: 'yalina' });
    expect(again.map((card) => [card.coach, card.at.toISOString()])).toStrictEqual([
      ['maotou', '2090-03-01T08:00:00.000Z'],
    ]);
    // It shows only in the squad it came in, and isn't given twice.
    expect(await messages.cardsFor({ member: me, squad: nextSquad, coach: 'maotou' })).toEqual([]);
    // Not for a member it doesn't name.
    expect(await messages.cardsFor({ member: other, squad, coach: 'maotou' })).toEqual([]);
    // Once it ended, a member who hadn't got it doesn't.
    now = new Date('2090-03-02T00:00:00Z');
    const late = await newMember();
    await messages.put({
      id,
      value: value({
        members: [me, late],
        startsAt: '2090-03-01T00:00:00Z',
        endsAt: '2090-03-02T00:00:00Z',
      }),
      by: me,
    });
    expect(await messages.cardsFor({ member: late, squad, coach: 'maotou' })).toEqual([]);
    expect(await messages.cardsFor({ member: me, squad, coach: 'maotou' })).toHaveLength(1);
  });

  it('keeps each part of an answer once, on a card reached, the first standing', async () => {
    const me = await newMember();
    const squad = SquadId.parse(randomUUID());
    const id = MessageId.parse(`m-${randomUUID().slice(0, 8)}`);
    now = new Date('2090-04-01T08:00:00Z');
    await messages.put({
      id,
      value: value({
        members: [me],
        startsAt: '2090-04-01T00:00:00Z',
        endsAt: '2090-04-02T00:00:00Z',
      }),
      by: me,
    });
    const answer = (path: string, part: Parameters<typeof messages.answer>[0]['part']) =>
      messages.answer({ member: me, squad, message: id, path: CardPath.parse(path), part });

    // Not got yet.
    await expect(answer('', { part: 'stars', stars: 4 })).rejects.toThrow(
      CoachMessageNotFoundError,
    );
    await messages.cardsFor({ member: me, squad, coach: 'maotou' });
    // Only in the squad it came in.
    await expect(
      messages.answer({
        member: me,
        squad: SquadId.parse(randomUUID()),
        message: id,
        path: CardPath.parse(''),
        part: { part: 'stars', stars: 4 },
      }),
    ).rejects.toThrow(CoachMessageNotFoundError);

    await answer('', { part: 'stars', stars: 4 });
    await answer('', { part: 'stars', stars: 1 });
    await answer('', { part: 'text', text: '  器械很新  ' });
    await expect(answer('', { part: 'text', text: '   ' })).rejects.toThrow(
      CoachMessageAnswerInvalidError,
    );
    await expect(answer('more', { part: 'text', text: '还有' })).rejects.toThrow(
      CoachMessageAnswerInvalidError,
    );
    await answer('', { part: 'tap', button: 'more' });
    const answered = await answer('more', { part: 'text', text: '人有点多' });
    expect(Object.fromEntries(answered)).toStrictEqual({
      '': { stars: 4, text: '器械很新', tap: 'more' },
      more: { text: '人有点多' },
    });

    const [card] = await messages.cardsFor({ member: me, squad, coach: 'maotou' });
    expect(Object.fromEntries(card?.answered ?? [])).toStrictEqual(Object.fromEntries(answered));
    const rows = await messages.answersTo(id);
    expect(rows.map((row) => [row.path, row.part])).toStrictEqual([
      ['', 'stars'],
      ['', 'text'],
      ['', 'tap'],
      ['more', 'text'],
    ]);
  });
});
