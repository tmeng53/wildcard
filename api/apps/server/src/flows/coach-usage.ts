import type { AiFeature, AiUsage } from '@wildcard/ai-usage';
import type { CoachUsage } from '@wildcard/coach';

// The coach's model calls in the AI usage ledger, with every other model call (Tracy,
// 2026-11-10): each run counted to its squad and the member it answered, and the coach off duty
// once the squad's AI budget for the day is spent.

/** The ledger's lines for the coach's runs, by kind. */
const FEATURES = {
  wake: 'coach-wake',
  letter: 'coach-letter',
  preview: 'coach-preview',
} as const satisfies Record<string, AiFeature>;

export function coachUsageIn(usage: AiUsage): CoachUsage {
  return {
    offDutyWhy: ({ squad, model }) => usage.blockedWhy({ payer: { squad }, model, capped: true }),
    record: ({ squad, member, kind, model, usage: tokens }) =>
      usage.record({
        feature: FEATURES[kind],
        payer: { squad, ...(member === undefined ? {} : { member }) },
        model,
        usage: tokens,
      }),
    total: async ({ squad, since }) => {
      const total = await usage.total({
        squad,
        features: Object.values(FEATURES),
        ...(since === undefined ? {} : { since }),
      });
      return {
        wakes: total.calls,
        requests: total.requests,
        inputTokens: total.inputTokens,
        cachedInputTokens: total.cachedInputTokens,
        outputTokens: total.outputTokens,
        costMicros: total.costMicros,
      };
    },
  };
}
