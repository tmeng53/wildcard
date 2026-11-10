import {
  AiBudgetSpentError,
  LanguageModelUnavailableError,
  type LanguageModel,
  type ModelPayer,
  type ProviderModel,
  type TokenUsage,
} from '@wildcard/language-model';
import { momentAt, NEW_YORK, wallClockAt } from '@wildcard/time-zones';

import { costMicros, ModelName, type AiFeature, type UsageTotal } from '../domain/usage.js';
import type {
  AiUsageLedger,
  AiUsageSettingsStore,
  Clock,
  SquadOf,
  SquadTimeZones,
} from '../ports.js';

/**
 * Every model call, counted to the member and squad it was for, and the daily budget they spend
 * (Tracy, 2026-11-10). A squad's budget runs over its own day; everyone's together over New
 * York's.
 */
export interface AiUsage {
  /**
   * Why a call to `model` for `payer` may not be made now, if it may not: the model has no price
   * (so its cost couldn't be counted), or, for a capped feature, the payer's squad or everyone
   * spent the day's budget.
   */
  blockedWhy(input: {
    readonly payer: ModelPayer;
    readonly model: string;
    readonly capped: boolean;
  }): Promise<string | undefined>;
  /** Records a call's tokens for `payer`, at the model's price now; returns their cost. */
  record(input: {
    readonly feature: AiFeature;
    readonly payer: ModelPayer;
    readonly model: string;
    readonly usage: TokenUsage;
  }): Promise<number>;
  /** A squad's calls for these features, since `since` or ever. */
  total(input: {
    readonly squad: string;
    readonly features: readonly AiFeature[];
    readonly since?: Date;
  }): Promise<UsageTotal>;
  /**
   * A provider's model that counts every call it makes for `feature` to its payer, recording
   * the tokens even of a call that failed. A capped feature's call isn't made once its payer's
   * budget is spent (`AiBudgetSpentError`); none is made to a model without a price
   * (`LanguageModelUnavailableError`).
   */
  meter(
    provider: ProviderModel,
    options: { readonly feature: AiFeature; readonly capped: boolean },
  ): LanguageModel;
}

export function createAiUsage(deps: {
  readonly settings: Pick<AiUsageSettingsStore, 'current'>;
  readonly ledger: AiUsageLedger;
  readonly timeZonesAt: SquadTimeZones;
  readonly squadOf: SquadOf;
  readonly clock: Clock;
}): AiUsage {
  /** The squad that pays for a call: the one named, else the member's now. */
  const squadOf = async (payer: ModelPayer): Promise<string | undefined> =>
    payer.squad?.toLowerCase() ??
    (payer.member === undefined ? undefined : (await deps.squadOf(payer.member))?.toLowerCase());

  const dayStart = (now: Date, zone: string) =>
    momentAt({ day: wallClockAt(now, zone).day, hour: 0, zone });

  /** Why a call may not be made: a model we can't count the cost of, or a spent budget. */
  type Blocked =
    | { readonly kind: 'unpriced'; readonly why: string }
    | { readonly kind: 'spent'; readonly why: string };

  const blocked = async ({
    payer,
    model,
    capped,
  }: Parameters<AiUsage['blockedWhy']>[0]): Promise<Blocked | undefined> => {
    const settings = await deps.settings.current();
    if (settings.prices[model] === undefined) {
      return { kind: 'unpriced', why: `${model} has no price` };
    }
    if (!capped) return undefined;
    const now = deps.clock();
    const squad = await squadOf(payer);
    if (squad !== undefined) {
      const zone = (await deps.timeZonesAt([squad], now))(squad);
      const spent = await deps.ledger.spent({ squad, since: dayStart(now, zone) });
      if (spent >= settings.squadDailyCapMicros) {
        return {
          kind: 'spent',
          why: `the squad spent ${String(spent)} of its ${String(settings.squadDailyCapMicros)} micros today`,
        };
      }
    }
    const everyone = await deps.ledger.spent({ since: dayStart(now, NEW_YORK) });
    if (everyone >= settings.dailyCapMicros) {
      return {
        kind: 'spent',
        why: `every squad spent ${String(everyone)} of the ${String(settings.dailyCapMicros)} micros today`,
      };
    }
    return undefined;
  };

  const record: AiUsage['record'] = async ({ feature, payer, model, usage }) => {
    const price = (await deps.settings.current()).prices[model];
    // A price taken away since the call was let through: its tokens still count, at nothing.
    const cost = price === undefined ? 0 : costMicros(usage, price);
    await deps.ledger.record({
      feature,
      squad: await squadOf(payer),
      member: payer.member?.toLowerCase(),
      model: ModelName.parse(model),
      usage,
      costMicros: cost,
      at: deps.clock(),
    });
    return cost;
  };

  return {
    blockedWhy: async (input) => (await blocked(input))?.why,
    record,
    total: (input) => deps.ledger.total({ ...input, squad: input.squad.toLowerCase() }),
    meter: (provider, { feature, capped }) => ({
      answer: async ({ payer, ...request }) => {
        const refused = await blocked({ payer, model: request.model, capped });
        // A missing price is ours to fix, not the payer's spending.
        if (refused?.kind === 'unpriced') {
          throw new LanguageModelUnavailableError({ cause: new Error(refused.why) });
        }
        if (refused?.kind === 'spent') throw new AiBudgetSpentError(refused.why);
        try {
          const { reply, usage } = await provider.answer(request);
          await record({ feature, payer, model: request.model, usage });
          return reply;
        } catch (error) {
          if (error instanceof LanguageModelUnavailableError && error.usage !== undefined) {
            await record({ feature, payer, model: request.model, usage: error.usage });
          }
          throw error;
        }
      },
    }),
  };
}
