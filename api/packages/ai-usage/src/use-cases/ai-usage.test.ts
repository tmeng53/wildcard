import {
  AiBudgetSpentError,
  LanguageModelUnavailableError,
  type ProviderModel,
  type TokenUsage,
} from '@wildcard/language-model';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { AiUsageSettings } from '../domain/settings.js';
import type { AiUsageLedger, UsageEntry } from '../ports.js';
import { createAiUsage } from './ai-usage.js';

const squad = '6f1c3e2a-8b4d-4c5e-9f60-7a8b9c0d1e2f';
const other = '7a1c3e2a-8b4d-4c5e-9f60-7a8b9c0d1e2f';
const mia = '11111111-1111-4111-8111-111111111111';
const loner = '22222222-2222-4222-8222-222222222222';

const settings = AiUsageSettings.parse({
  version: 1,
  prices: {
    'openai/gpt-6-luna': {
      inputMicrosPerMillion: 1_000_000,
      cachedInputMicrosPerMillion: 0,
      outputMicrosPerMillion: 0,
    },
  },
  squadDailyCapMicros: 100,
  dailyCapMicros: 1_000,
});

/** A ledger in memory: what was recorded, and what it adds up to. */
function memoryLedger(entries: UsageEntry[] = []): AiUsageLedger & { entries: UsageEntry[] } {
  return {
    entries,
    record: (entry) => {
      entries.push(entry);
      return Promise.resolve();
    },
    spent: ({ squad: of, since }) =>
      Promise.resolve(
        entries
          .filter((entry) => entry.at >= since && (of === undefined || entry.squad === of))
          .reduce((sum, entry) => sum + entry.costMicros, 0),
      ),
    total: () => Promise.reject(new Error('not used')),
  };
}

const spending = (
  cost: number,
  { at, of = squad }: { at: string; of?: string | null },
): UsageEntry => ({
  feature: 'coach-wake',
  squad: of ?? undefined,
  member: undefined,
  model: 'openai/gpt-6-luna',
  usage: { requests: 1, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 },
  costMicros: cost,
  at: new Date(at),
});

function usageAt(
  now: string,
  {
    ledger = memoryLedger(),
    zone = 'Asia/Shanghai',
  }: { ledger?: ReturnType<typeof memoryLedger>; zone?: string } = {},
) {
  return {
    ledger,
    usage: createAiUsage({
      settings: { current: () => Promise.resolve(settings) },
      ledger,
      // The squad keeps Shanghai's day: 2026-11-10 starts at 2026-11-09T16:00Z.
      timeZonesAt: () => Promise.resolve(() => zone),
      squadOf: (member) => Promise.resolve(member === mia ? squad : undefined),
      clock: () => new Date(now),
    }),
  };
}

const used: TokenUsage = { requests: 2, inputTokens: 30, cachedInputTokens: 0, outputTokens: 5 };

const answering = (answer: () => Promise<{ reply: unknown; usage: TokenUsage }>) => {
  const calls: unknown[] = [];
  const provider: ProviderModel = {
    answer: async (request) => {
      calls.push(request);
      const { reply, usage } = await answer();
      return { reply: request.reply.parse(reply), usage };
    },
  };
  return { provider, calls };
};

const request = {
  model: 'openai/gpt-6-luna',
  instructions: 'say hi',
  prompt: 'hi',
  reply: z.strictObject({ line: z.string() }),
};

describe('the AI budget', () => {
  it('lets a call through until the squad spent its cap over its own day', async () => {
    const { usage } = usageAt('2026-11-10T03:00:00Z', {
      ledger: memoryLedger([
        // Before Shanghai's day began: yesterday's.
        spending(500, { at: '2026-11-09T15:59:59Z' }),
        spending(99, { at: '2026-11-09T16:00:00Z' }),
        // Another squad's spending is its own.
        spending(300, { at: '2026-11-10T01:00:00Z', of: other }),
      ]),
    });
    const capped = { model: 'openai/gpt-6-luna', capped: true };
    expect(await usage.blockedWhy({ ...capped, payer: { squad } })).toBeUndefined();
    // A member's call is their squad's.
    expect(await usage.blockedWhy({ ...capped, payer: { member: mia } })).toBeUndefined();

    const { usage: later } = usageAt('2026-11-10T03:00:00Z', {
      ledger: memoryLedger([spending(100, { at: '2026-11-09T16:00:00Z' })]),
    });
    expect(await later.blockedWhy({ ...capped, payer: { squad } })).toBe(
      'the squad spent 100 of its 100 micros today',
    );
    expect(await later.blockedWhy({ ...capped, payer: { member: mia } })).toBe(
      'the squad spent 100 of its 100 micros today',
    );
    // A member without a squad pays from no squad's budget.
    expect(await later.blockedWhy({ ...capped, payer: { member: loner } })).toBeUndefined();
    // An uncapped feature (the weekly awards) is counted but never held back.
    expect(
      await later.blockedWhy({ model: 'openai/gpt-6-luna', capped: false, payer: { squad } }),
    ).toBeUndefined();

    // The squad's next day, on its clock, starts afresh.
    const { usage: tomorrow } = usageAt('2026-11-10T16:00:00Z', {
      ledger: memoryLedger([spending(100, { at: '2026-11-09T16:00:00Z' })]),
    });
    expect(await tomorrow.blockedWhy({ ...capped, payer: { squad } })).toBeUndefined();
  });

  it('holds every squad back once everyone spent the cap over New York’s day', async () => {
    // New York's 2026-11-10 starts at 05:00Z.
    const ledger = memoryLedger([
      spending(1_000, { at: '2026-11-10T04:59:59Z', of: other }),
      spending(999, { at: '2026-11-10T05:00:00Z', of: null }),
    ]);
    const { usage } = usageAt('2026-11-10T12:00:00Z', { ledger, zone: 'America/New_York' });
    const capped = { model: 'openai/gpt-6-luna', capped: true };
    expect(await usage.blockedWhy({ ...capped, payer: { member: loner } })).toBeUndefined();
    ledger.entries.push(spending(1, { at: '2026-11-10T06:00:00Z', of: other }));
    expect(await usage.blockedWhy({ ...capped, payer: { member: loner } })).toBe(
      'every squad spent 1000 of the 1000 micros today',
    );
    expect(await usage.blockedWhy({ ...capped, payer: { squad } })).toBe(
      'every squad spent 1000 of the 1000 micros today',
    );
  });

  it('never lets a call to a model without a price through', async () => {
    const { usage } = usageAt('2026-11-10T12:00:00Z');
    expect(
      await usage.blockedWhy({ model: 'anthropic/claude-x', capped: false, payer: { squad } }),
    ).toBe('anthropic/claude-x has no price');
  });
});

describe('a metered model', () => {
  it('counts a call to its payer: the member, and the squad they are in', async () => {
    const { usage, ledger } = usageAt('2026-11-10T12:00:00Z');
    const { provider } = answering(() => Promise.resolve({ reply: { line: 'hi' }, usage: used }));
    const model = usage.meter(provider, { feature: 'disclaimer-drafts', capped: true });
    expect(await model.answer({ ...request, payer: { member: mia.toUpperCase() } })).toStrictEqual({
      line: 'hi',
    });
    expect(ledger.entries).toStrictEqual([
      {
        feature: 'disclaimer-drafts',
        squad,
        member: mia,
        model: 'openai/gpt-6-luna',
        usage: used,
        costMicros: 30,
        at: new Date('2026-11-10T12:00:00Z'),
      },
    ]);
  });

  it('counts a call for a squad to the squad, and one for a member without a squad to no squad', async () => {
    const { usage, ledger } = usageAt('2026-11-10T12:00:00Z');
    const { provider } = answering(() => Promise.resolve({ reply: { line: 'hi' }, usage: used }));
    const model = usage.meter(provider, { feature: 'weekly-awards', capped: false });
    await model.answer({ ...request, payer: { squad } });
    await model.answer({ ...request, payer: { member: loner } });
    expect(ledger.entries.map(({ squad: of, member }) => ({ of, member }))).toStrictEqual([
      { of: squad, member: undefined },
      { of: undefined, member: loner },
    ]);
  });

  it('counts what a failed call spent, and throws its error', async () => {
    const { usage, ledger } = usageAt('2026-11-10T12:00:00Z');
    const failure = new LanguageModelUnavailableError({ usage: used });
    const { provider } = answering(() => Promise.reject(failure));
    const model = usage.meter(provider, { feature: 'coach-letter', capped: true });
    await expect(model.answer({ ...request, payer: { squad } })).rejects.toBe(failure);
    expect(ledger.entries.map(({ costMicros }) => costMicros)).toStrictEqual([30]);

    // One that spent nothing (it never reached the provider) counts nothing.
    const { provider: down } = answering(() => Promise.reject(new LanguageModelUnavailableError()));
    await expect(
      usage.meter(down, { feature: 'coach-letter', capped: true }).answer({
        ...request,
        payer: { squad },
      }),
    ).rejects.toBeInstanceOf(LanguageModelUnavailableError);
    expect(ledger.entries).toHaveLength(1);
  });

  it('makes no call once its payer’s budget is spent, or to a model without a price', async () => {
    const { usage, ledger } = usageAt('2026-11-10T03:00:00Z', {
      ledger: memoryLedger([spending(100, { at: '2026-11-09T16:00:00Z' })]),
    });
    const { provider, calls } = answering(() =>
      Promise.resolve({ reply: { line: 'hi' }, usage: used }),
    );
    await expect(
      usage
        .meter(provider, { feature: 'disclaimer-drafts', capped: true })
        .answer({ ...request, payer: { member: mia } }),
    ).rejects.toBeInstanceOf(AiBudgetSpentError);
    await expect(
      usage
        .meter(provider, { feature: 'weekly-awards', capped: false })
        .answer({ ...request, model: 'openai/unpriced', payer: { squad } }),
    ).rejects.toBeInstanceOf(LanguageModelUnavailableError);
    expect(calls).toStrictEqual([]);
    expect(ledger.entries).toHaveLength(1);

    // The awards aren't capped: the spent budget doesn't hold them back.
    await usage
      .meter(provider, { feature: 'weekly-awards', capped: false })
      .answer({ ...request, payer: { squad } });
    expect(calls).toHaveLength(1);
  });
});
