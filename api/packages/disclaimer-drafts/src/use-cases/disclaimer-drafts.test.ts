import { randomUUID } from 'node:crypto';

import { isAppError } from '@wildcard/errors';
import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresDraftAllowance,
  type DisclaimerDraftTables,
} from '../adapters/postgres-draft-allowance.js';
import { createPostgresDraftSettings } from '../adapters/postgres-draft-settings.js';
import { DraftReason, MemberId, type PromptMeme } from '../domain/draft-request.js';
import type { DraftSettings } from '../domain/settings.js';
import type { ModelReply } from '../domain/drafts.js';
import { DisclaimerWriterUnavailableError } from '../errors.js';
import type { LanguageModel } from '../ports.js';
import { createDisclaimerDrafts } from './disclaimer-drafts.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database. The
// model is the port's: it answers what each test sets and remembers what it was asked. The
// settings are the database's, as the migration first saved them, with what a test changes on top.
const db = new Kysely<DisclaimerDraftTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

const good: ModelReply = {
  version: 1,
  outcome: 'drafts',
  drafts: [
    '闹钟响了三次，我和被子的谈判进入加时赛，目前被子领先。',
    '本人身体已到岗，灵魂仍在床上办理延期手续。',
    '经核实，早上那句「再眯五分钟」实际时长为两小时。',
  ],
};

function setup(
  options: {
    answer?: () => Promise<unknown>;
    memes?: PromptMeme[];
    /** The random numbers the use case draws, in order; the last one repeats. */
    rolls?: number[];
    now?: Date;
    consentsToAi?: boolean;
    settings?: Partial<DraftSettings>;
  } = {},
) {
  const rolls = options.rolls ?? [0.99];
  let drawn = 0;
  const prompts: string[] = [];
  const asked: { model: string; instructions: string }[] = [];
  const model: LanguageModel = {
    answer: async ({ model, instructions, prompt, reply }) => {
      prompts.push(prompt);
      asked.push({ model, instructions });
      return reply.parse(await (options.answer ?? (() => Promise.resolve(good)))());
    },
  };
  let now = options.now ?? new Date('2026-10-19T04:00:00.000Z');
  const saved = createPostgresDraftSettings(db);
  const drafts = createDisclaimerDrafts({
    model,
    settings: {
      ...saved,
      current: async () => ({ ...(await saved.current()), ...options.settings }),
    },
    memes: () => Promise.resolve(options.memes ?? []),
    allowance: createPostgresDraftAllowance(db),
    aiConsent: () => Promise.resolve(options.consentsToAi ?? true),
    clock: () => now,
    random: () => rolls[Math.min(drawn++, rolls.length - 1)] ?? 0,
  });
  return {
    drafts,
    prompts,
    asked,
    later: (ms: number) => {
      now = new Date(now.getTime() + ms);
    },
  };
}

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

const request = (member: MemberId, reason = '早上没起来') => ({
  member,
  reason: DraftReason.parse(reason),
  style: 'funny' as const,
});

async function reasonOf(promise: Promise<unknown>) {
  try {
    await promise;
    return 'ok';
  } catch (error) {
    return isAppError(error) ? error.reason : error;
  }
}

describe('createDisclaimerDrafts', () => {
  it('writes three drafts from the reason and style', async () => {
    const { drafts, prompts } = setup();
    const member = await newMember();
    expect(await drafts.write(request(member))).toEqual({ kind: 'drafts', drafts: good.drafts });
    expect(prompts).toEqual(['原因：早上没起来\n风格：搞笑']);
  });

  it('asks the model the settings name, with their instructions', async () => {
    const { drafts, asked } = setup();
    await drafts.write(request(await newMember()));
    expect(asked).toHaveLength(1);
    expect(asked[0]?.model).toBe('openai/gpt-6-luna');
    expect(asked[0]?.instructions).toMatch(/^你在帮一个朋友运动打卡 App 的用户写「请假条」/u);
    expect(asked[0]?.instructions).toContain('"outcome":"selfHarm"');
  });

  it('refuses while the settings turn drafts off, without asking the model or counting', async () => {
    const member = await newMember();
    const off = setup({ settings: { writing: false } });
    expect(await reasonOf(off.drafts.write(request(member)))).toBe('DISCLAIMER_WRITER_UNAVAILABLE');
    expect(off.prompts).toStrictEqual([]);
    expect(
      await db
        .selectFrom('disclaimer_draft_requests')
        .select('id')
        .where('member_id', '=', member)
        .execute(),
    ).toStrictEqual([]);
  });

  it('gives each member as many batches as the settings say', async () => {
    const { drafts } = setup({ settings: { batchesPerDay: 2 } });
    const member = await newMember();
    expect(await reasonOf(drafts.write(request(member)))).toBe('ok');
    expect(await reasonOf(drafts.write(request(member)))).toBe('ok');
    expect(await reasonOf(drafts.write(request(member)))).toBe('DISCLAIMER_DRAFTS_USED_UP');
  });

  it('gives each member 6 batches a day, then refuses until a day has passed', async () => {
    const { drafts, later } = setup();
    const [member, other] = [await newMember(), await newMember()];
    for (let batch = 0; batch < 6; batch += 1) {
      expect(await reasonOf(drafts.write(request(member)))).toBe('ok');
      later(60_000);
    }
    expect(await reasonOf(drafts.write(request(member)))).toBe('DISCLAIMER_DRAFTS_USED_UP');
    expect(await reasonOf(drafts.write(request(other)))).toBe('ok');
    // The first batch was 6 minutes ago; 24 hours after it, one batch comes back.
    later(86_400_000 - 6 * 60_000);
    expect(await reasonOf(drafts.write(request(member)))).toBe('ok');
    expect(await reasonOf(drafts.write(request(member)))).toBe('DISCLAIMER_DRAFTS_USED_UP');
  });

  it('lets only 6 of many requests at once through', async () => {
    const { drafts } = setup();
    const member = await newMember();
    const results = await Promise.all(
      Array.from({ length: 10 }, () => reasonOf(drafts.write(request(member)))),
    );
    expect(results.filter((result) => result === 'ok')).toHaveLength(6);
    expect(results.filter((result) => result === 'DISCLAIMER_DRAFTS_USED_UP')).toHaveLength(4);
  });

  it('doesn’t count a batch the model failed or that failed the checks', async () => {
    const member = await newMember();
    const down = setup({ answer: () => Promise.reject(new DisclaimerWriterUnavailableError()) });
    const short = setup({
      answer: () => Promise.resolve({ ...good, drafts: ['太短了。', 'a', 'b'] }),
    });
    for (let attempt = 0; attempt < 4; attempt += 1) {
      expect(await reasonOf(down.drafts.write(request(member)))).toBe(
        'DISCLAIMER_WRITER_UNAVAILABLE',
      );
      expect(await reasonOf(short.drafts.write(request(member)))).toBe(
        'DISCLAIMER_WRITER_UNAVAILABLE',
      );
    }
    const { drafts } = setup();
    for (let batch = 0; batch < 6; batch += 1) {
      expect(await reasonOf(drafts.write(request(member)))).toBe('ok');
    }
  });

  it('refuses a member without a current AI consent, without asking the model', async () => {
    const { drafts, prompts } = setup({ consentsToAi: false });
    const member = await newMember();
    expect(await reasonOf(drafts.write(request(member)))).toBe('AI_CONSENT_REQUIRED');
    expect(prompts).toStrictEqual([]);
    expect(
      await db
        .selectFrom('disclaimer_draft_requests')
        .select('id')
        .where('member_id', '=', member)
        .execute(),
    ).toStrictEqual([]);
  });

  it('answers the care line or a decline when the model says so, with no word list of its own', async () => {
    const member = await newMember();
    const care = setup({
      answer: () => Promise.resolve({ version: 1, outcome: 'selfHarm', drafts: [] }),
    });
    expect(await care.drafts.write(request(member, '想自杀'))).toEqual({ kind: 'care' });
    expect(care.prompts).toHaveLength(1);
    const unsafe = setup({
      answer: () => Promise.resolve({ version: 1, outcome: 'unsafe', drafts: [] }),
    });
    expect(await unsafe.drafts.write(request(member))).toEqual({ kind: 'declined' });
  });

  const meme = (phrase: string, styles: PromptMeme['styles']): PromptMeme => ({
    phrase,
    meaning: `${phrase}的意思`,
    background: `${phrase}的背景`,
    styles,
  });
  const memes = [
    meme('只适合嘴硬', ['stubborn']),
    meme('班味', ['funny']),
    meme('松弛感', ['funny']),
  ];

  it('sends one meme that suits the style on a roll under 0.3, picked by the next roll', async () => {
    const { drafts, prompts } = setup({ memes, rolls: [0.29, 0.6] });
    await drafts.write(request(await newMember()));
    expect(prompts[0]).toBe(
      '原因：早上没起来\n风格：搞笑\n本周梗：松弛感\n  意思：松弛感的意思\n  背景：松弛感的背景',
    );
  });

  it.each([0.3, 0.99])('sends no meme on a roll of %s', async (roll) => {
    const { drafts, prompts } = setup({ memes, rolls: [roll, 0] });
    await drafts.write(request(await newMember()));
    expect(prompts[0]).toBe('原因：早上没起来\n风格：搞笑');
  });

  it('sends a meme as often as the settings say', async () => {
    const always = setup({ memes, rolls: [0.99, 0], settings: { memeChance: 1 } });
    await always.drafts.write(request(await newMember()));
    expect(always.prompts[0]).toContain('本周梗：班味');
    const never = setup({ memes, rolls: [0, 0], settings: { memeChance: 0 } });
    await never.drafts.write(request(await newMember()));
    expect(never.prompts[0]).toBe('原因：早上没起来\n风格：搞笑');
  });

  it('sends no meme when none suits the style', async () => {
    const { drafts, prompts } = setup({ memes: [memes[0] ?? meme('', [])], rolls: [0] });
    await drafts.write(request(await newMember()));
    expect(prompts[0]).toBe('原因：早上没起来\n风格：搞笑');
  });
});
