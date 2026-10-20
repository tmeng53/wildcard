import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import {
  createPostgresConsentStore,
  type AiConsentTables,
} from '../adapters/postgres-consent-store.js';
import { MemberId } from '../domain/ai-consent.js';
import { createAiConsent } from './ai-consent.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<AiConsentTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

function consentTo(copyVersion: number, start = '2026-10-20T05:00:00.000Z') {
  let now = new Date(start);
  const consent = createAiConsent({
    store: createPostgresConsentStore(db),
    copyVersion,
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

const rowsOf = (member: MemberId) =>
  db
    .selectFrom('ai_consents')
    .select(['copy_version', 'given_at'])
    .where('member_id', '=', member)
    .orderBy('copy_version')
    .execute();

describe('giving consent', () => {
  it('starts with none, then records the current copy version and when', async () => {
    const { consent } = consentTo(1);
    const member = await newMember();
    expect(await consent.find(member)).toStrictEqual({
      copyVersion: 1,
      given: undefined,
      current: false,
    });
    const given = { copyVersion: 1, givenAt: new Date('2026-10-20T05:00:00.000Z') };
    expect(await consent.give({ member, copyVersion: 1 })).toStrictEqual({
      copyVersion: 1,
      given,
      current: true,
    });
    expect(await consent.find(member)).toStrictEqual({ copyVersion: 1, given, current: true });
    expect(await consent.hasCurrent(member)).toBe(true);
  });

  it('keeps the first consent when it is given again, even at once', async () => {
    const { consent, later } = consentTo(1);
    const member = await newMember();
    await consent.give({ member, copyVersion: 1 });
    later(60_000);
    const again = await Promise.all([1, 2, 3].map(() => consent.give({ member, copyVersion: 1 })));
    expect(again.map((state) => state.given?.givenAt)).toStrictEqual(
      Array.from({ length: 3 }, () => new Date('2026-10-20T05:00:00.000Z')),
    );
    expect(await rowsOf(member)).toHaveLength(1);
  });

  it('refuses a version that isn’t the current one', async () => {
    const { consent } = consentTo(2);
    const member = await newMember();
    for (const copyVersion of [1, 3]) {
      await expect(consent.give({ member, copyVersion })).rejects.toMatchObject({
        reason: 'AI_CONSENT_COPY_OUTDATED',
      });
    }
    expect(await rowsOf(member)).toStrictEqual([]);
  });
});

describe('a new copy version', () => {
  it('makes an old consent stop counting until the member agrees again, keeping both', async () => {
    const member = await newMember();
    await consentTo(1).consent.give({ member, copyVersion: 1 });
    const { consent } = consentTo(2, '2026-11-01T05:00:00.000Z');
    expect(await consent.find(member)).toStrictEqual({
      copyVersion: 2,
      given: { copyVersion: 1, givenAt: new Date('2026-10-20T05:00:00.000Z') },
      current: false,
    });
    expect(await consent.hasCurrent(member)).toBe(false);
    expect(await consent.currentAmong([member])).toStrictEqual(new Set());

    await consent.give({ member, copyVersion: 2 });
    expect(await consent.hasCurrent(member)).toBe(true);
    expect(await rowsOf(member)).toStrictEqual([
      { copy_version: 1, given_at: new Date('2026-10-20T05:00:00.000Z') },
      { copy_version: 2, given_at: new Date('2026-11-01T05:00:00.000Z') },
    ]);
  });
});

describe('who among members has agreed', () => {
  it('names only those who agreed to the current copy', async () => {
    const { consent } = consentTo(2);
    const [agreed, never, outdated] = [await newMember(), await newMember(), await newMember()];
    await consent.give({ member: agreed, copyVersion: 2 });
    await consentTo(1).consent.give({ member: outdated, copyVersion: 1 });
    expect(await consent.currentAmong([agreed, never, outdated])).toStrictEqual(new Set([agreed]));
    expect(await consent.currentAmong([])).toStrictEqual(new Set());
  });
});

describe('deleting an account', () => {
  it('deletes the member’s consents with it', async () => {
    const member = await newMember();
    await consentTo(1).consent.give({ member, copyVersion: 1 });
    await sql`delete from auth.users where id = ${member}`.execute(db);
    expect(await rowsOf(member)).toStrictEqual([]);
  });
});
