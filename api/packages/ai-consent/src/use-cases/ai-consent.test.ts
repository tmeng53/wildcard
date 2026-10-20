import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresConsentStore,
  type AiConsentTables,
} from '../adapters/postgres-consent-store.js';
import { MemberId, type AiConsentTerms } from '../domain/ai-consent.js';
import { createAiConsent } from './ai-consent.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<AiConsentTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

const v1: AiConsentTerms = { copyVersion: 1, provider: 'openai' };

function consentWith(terms: AiConsentTerms, start = '2026-10-20T05:00:00.000Z') {
  let now = new Date(start);
  const consent = createAiConsent({
    store: createPostgresConsentStore(db),
    terms,
    clock: () => now,
  });
  return {
    consent,
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

describe('giving consent', () => {
  it('starts with none, then records the current terms and when', async () => {
    const { consent } = consentWith(v1);
    const member = await newMember();
    expect(await consent.find(member)).toStrictEqual({
      terms: v1,
      given: undefined,
      current: false,
    });
    const given = { terms: v1, givenAt: new Date('2026-10-20T05:00:00.000Z') };
    expect(await consent.give({ member, terms: v1 })).toStrictEqual({
      terms: v1,
      given,
      current: true,
    });
    expect(await consent.find(member)).toStrictEqual({ terms: v1, given, current: true });
    expect(await consent.hasCurrent(member)).toBe(true);
  });

  it('keeps the first consent when it is given again', async () => {
    const { consent, later } = consentWith(v1);
    const member = await newMember();
    await consent.give({ member, terms: v1 });
    later(60_000);
    const again = await consent.give({ member, terms: v1 });
    expect(again.given?.givenAt).toStrictEqual(new Date('2026-10-20T05:00:00.000Z'));
    const rows = await db
      .selectFrom('ai_consents')
      .select('id')
      .where('member_id', '=', member)
      .execute();
    expect(rows).toHaveLength(1);
  });

  it('refuses terms that aren’t the current ones', async () => {
    const { consent } = consentWith(v1);
    const member = await newMember();
    for (const terms of [
      { copyVersion: 2, provider: 'openai' },
      { copyVersion: 1, provider: 'anthropic' },
    ] as const) {
      await expect(consent.give({ member, terms })).rejects.toMatchObject({
        reason: 'AI_CONSENT_TERMS_OUTDATED',
      });
    }
    expect(await consent.hasCurrent(member)).toBe(false);
  });
});

describe('new terms', () => {
  it('make an old consent stop counting until the member agrees again', async () => {
    const member = await newMember();
    await consentWith(v1).consent.give({ member, terms: v1 });
    const v2: AiConsentTerms = { copyVersion: 2, provider: 'openai' };
    const anthropic: AiConsentTerms = { copyVersion: 1, provider: 'anthropic' };
    for (const terms of [v2, anthropic]) {
      const { consent } = consentWith(terms, '2026-10-21T05:00:00.000Z');
      const state = await consent.find(member);
      expect([state.given?.terms, state.current]).toStrictEqual([v1, false]);
      expect(await consent.currentAmong([member])).toStrictEqual(new Set());
    }
    const { consent } = consentWith(v2, '2026-10-21T05:00:00.000Z');
    await consent.give({ member, terms: v2 });
    expect(await consent.find(member)).toStrictEqual({
      terms: v2,
      given: { terms: v2, givenAt: new Date('2026-10-21T05:00:00.000Z') },
      current: true,
    });
  });
});

describe('withdrawing consent', () => {
  it('ends it, keeps the record, and can be repeated or given again', async () => {
    const { consent, later } = consentWith(v1);
    const member = await newMember();
    await consent.give({ member, terms: v1 });
    later(60_000);
    await consent.withdraw(member);
    await consent.withdraw(member);
    expect(await consent.find(member)).toStrictEqual({
      terms: v1,
      given: undefined,
      current: false,
    });
    const rows = await db
      .selectFrom('ai_consents')
      .select(['given_at', 'withdrawn_at'])
      .where('member_id', '=', member)
      .execute();
    expect(rows.map((row) => [row.given_at, row.withdrawn_at])).toStrictEqual([
      [new Date('2026-10-20T05:00:00.000Z'), new Date('2026-10-20T05:01:00.000Z')],
    ]);
    later(60_000);
    await consent.give({ member, terms: v1 });
    expect(await consent.hasCurrent(member)).toBe(true);
  });
});

describe('who among members has consented', () => {
  it('names only those whose latest consent is to the current terms', async () => {
    const { consent } = consentWith(v1);
    const [agreed, withdrew, never, outdated] = [
      await newMember(),
      await newMember(),
      await newMember(),
      await newMember(),
    ];
    await consent.give({ member: agreed, terms: v1 });
    await consent.give({ member: withdrew, terms: v1 });
    await consent.withdraw(withdrew);
    await createAiConsent({
      store: createPostgresConsentStore(db),
      terms: { copyVersion: 1, provider: 'anthropic' },
      clock: () => new Date('2026-10-21T05:00:00.000Z'),
    }).give({ member: outdated, terms: { copyVersion: 1, provider: 'anthropic' } });
    await consent.give({ member: outdated, terms: v1 });
    expect(await consent.currentAmong([agreed, withdrew, never, outdated])).toStrictEqual(
      new Set([agreed]),
    );
    expect(await consent.currentAmong([])).toStrictEqual(new Set());
  });
});
