import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresMemeStore, type MemeTables } from '../adapters/postgres-meme-store.js';
import { MemeDraft } from '../domain/meme.js';
import { MemeNotFoundError } from '../errors.js';
import { createMemes } from './memes.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<MemeTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

let now = new Date('2026-10-19T16:00:00.000Z');
const memes = createMemes({ store: createPostgresMemeStore(db), clock: () => now });
const DAY = 86_400_000;

/** A meme with a phrase no other test uses (the tests share one database). */
function draft(name: string) {
  return MemeDraft.parse({
    phrase: `${name}${randomUUID().slice(0, 8)}`,
    background: '2024 年一个外国博主在中国街头问路人「city不city啊」，口音魔性，迅速走红。',
    meaning: '问某事洋不洋气、时髦不时髦。',
    styles: ['funny', 'stubborn'],
    source: '抖音',
  });
}

/** The memes in use now, among the ones a test made. */
async function inUse(...made: readonly MemeDraft[]) {
  const phrases = new Set(made.map(({ phrase }) => phrase));
  return (await memes.listInUse()).filter(({ phrase }) => phrases.has(phrase));
}

describe('the meme library', () => {
  it('keeps an approved meme with its background, meaning, styles and source', async () => {
    const city = draft('city不city');
    now = new Date('2026-10-19T16:00:00.000Z');
    await expect(memes.addApproved({ memes: [city], approvedAt: now })).resolves.toStrictEqual({
      added: [city.phrase],
      alreadyThere: [],
    });
    const [saved, ...rest] = await inUse(city);
    expect(rest).toStrictEqual([]);
    const { id, ...kept } = saved ?? { id: undefined };
    expect(z.uuid().safeParse(id).success).toBe(true);
    expect(kept).toStrictEqual({ ...city, approvedAt: new Date('2026-10-19T16:00:00.000Z') });
  });

  it('adds a meme once, so approving the same batch again changes nothing', async () => {
    const first = draft('松弛感');
    const second = draft('班味');
    const approvedAt = new Date('2026-10-19T16:00:00.000Z');
    await memes.addApproved({ memes: [first], approvedAt });
    await expect(
      memes.addApproved({
        memes: [{ ...first, meaning: '换了个说法' }, second],
        approvedAt: new Date('2026-10-20T16:00:00.000Z'),
      }),
    ).resolves.toStrictEqual({ added: [second.phrase], alreadyThere: [first.phrase] });
    const kept = await inUse(first);
    expect(kept.map(({ meaning, approvedAt: at }) => [meaning, at])).toStrictEqual([
      [first.meaning, approvedAt],
    ]);
  });

  it('adds a phrase listed twice in one batch once', async () => {
    const meme = draft('重复');
    await expect(
      memes.addApproved({ memes: [meme, meme], approvedAt: new Date('2026-10-19T16:00:00.000Z') }),
    ).resolves.toStrictEqual({ added: [meme.phrase], alreadyThere: [] });
    expect(await inUse(meme)).toHaveLength(1);
  });

  it('uses a meme for 4 weeks after its approval, newest first', async () => {
    const old = draft('旧梗');
    const recent = draft('新梗');
    const approved = new Date('2026-10-19T16:00:00.000Z');
    await memes.addApproved({ memes: [old], approvedAt: approved });
    await memes.addApproved({ memes: [recent], approvedAt: new Date(approved.getTime() + DAY) });

    now = new Date(approved.getTime() + 28 * DAY);
    expect((await inUse(old, recent)).map(({ phrase }) => phrase)).toStrictEqual([
      recent.phrase,
      old.phrase,
    ]);
    now = new Date(approved.getTime() + 28 * DAY + 1);
    expect((await inUse(old, recent)).map(({ phrase }) => phrase)).toStrictEqual([recent.phrase]);
  });

  it('waits for a meme dated ahead until its day comes', async () => {
    const meme = draft('明天的梗');
    const approvedAt = new Date('2026-10-20T16:00:00.000Z');
    await memes.addApproved({ memes: [meme], approvedAt });
    now = new Date(approvedAt.getTime() - 1);
    expect(await inUse(meme)).toStrictEqual([]);
    now = approvedAt;
    expect((await inUse(meme)).map(({ phrase }) => phrase)).toStrictEqual([meme.phrase]);
  });

  it('never uses a meme again once it is turned off', async () => {
    const meme = draft('下头');
    now = new Date('2026-10-19T16:00:00.000Z');
    await memes.addApproved({ memes: [meme], approvedAt: now });
    await memes.turnOff(meme.phrase);
    await memes.turnOff(meme.phrase);
    expect(await inUse(meme)).toStrictEqual([]);
  });

  it('says so when the meme to turn off is not in the library', async () => {
    await expect(memes.turnOff(`没有这个梗${randomUUID()}`)).rejects.toBeInstanceOf(
      MemeNotFoundError,
    );
  });
});
