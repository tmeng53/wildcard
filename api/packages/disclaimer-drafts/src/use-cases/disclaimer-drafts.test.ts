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
import { DraftReason, MemberId, type PromptMeme } from '../domain/draft-request.js';
import type { ModelReply } from '../domain/drafts.js';
import { DisclaimerWriterUnavailableError } from '../errors.js';
import type { LanguageModel } from '../ports.js';
import { createDisclaimerDrafts } from './disclaimer-drafts.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database. The
// model is the port's: it answers what each test sets and remembers what it was asked.
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
  options: { answer?: () => Promise<unknown>; memes?: PromptMeme[]; now?: Date } = {},
) {
  const prompts: string[] = [];
  const model: LanguageModel = {
    answer: async ({ prompt, reply }) => {
      prompts.push(prompt);
      return reply.parse(await (options.answer ?? (() => Promise.resolve(good)))());
    },
  };
  let now = options.now ?? new Date('2026-10-19T04:00:00.000Z');
  const drafts = createDisclaimerDrafts({
    model,
    memes: () => Promise.resolve(options.memes ?? []),
    allowance: createPostgresDraftAllowance(db),
    clock: () => now,
  });
  return {
    drafts,
    prompts,
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

  it('answers the care line for a reason about self-harm, without asking the model', async () => {
    const { drafts, prompts } = setup();
    const member = await newMember();
    expect(await drafts.write(request(member, '想自杀'))).toEqual({ kind: 'care' });
    expect(prompts).toEqual([]);
  });

  it('answers what the model decides for subtler reasons', async () => {
    const member = await newMember();
    const care = setup({
      answer: () => Promise.resolve({ version: 1, outcome: 'selfHarm', drafts: [] }),
    });
    expect(await care.drafts.write(request(member, '最近觉得撑不下去了'))).toEqual({
      kind: 'care',
    });
    const unsafe = setup({
      answer: () => Promise.resolve({ version: 1, outcome: 'unsafe', drafts: [] }),
    });
    expect(await unsafe.drafts.write(request(member))).toEqual({ kind: 'declined' });
  });

  it('lists only this week’s memes that suit the style, at most 8', async () => {
    const meme = (phrase: string, styles: PromptMeme['styles']): PromptMeme => ({
      phrase,
      meaning: '意思',
      background: '背景',
      styles,
    });
    const memes = [
      meme('只适合嘴硬', ['stubborn']),
      ...Array.from({ length: 9 }, (_, index) => meme(`梗${String(index)}`, ['funny'])),
    ];
    const { drafts, prompts } = setup({ memes });
    await drafts.write(request(await newMember()));
    const prompt = prompts[0] ?? '';
    expect(prompt).not.toContain('只适合嘴硬');
    expect(prompt.match(/- 梗：/gu)).toHaveLength(8);
    expect(prompt).toContain('- 梗：梗7');
    expect(prompt).not.toContain('- 梗：梗8');
  });
});
