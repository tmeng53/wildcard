// @wildcard/ai-usage: every language-model call, counted to the member and squad it was for (the
// ledger), what models cost, and the daily budget a squad's calls and everyone's spend.

export { createPostgresAiUsageLedger } from './adapters/postgres-ai-usage-ledger.js';
export {
  createPostgresAiUsageSettings,
  type AiUsageTables,
} from './adapters/postgres-ai-usage-settings.js';
export { AiUsageSettings, AiUsageSettingsChange, MemberId } from './domain/settings.js';
export { AiFeature, costMicros, ModelName, ModelPrice, type UsageTotal } from './domain/usage.js';
export type {
  AiUsageLedger,
  AiUsageSettingsStore,
  Clock,
  SquadOf,
  SquadTimeZones,
  UsageEntry,
} from './ports.js';
export { createAiUsage, type AiUsage } from './use-cases/ai-usage.js';
export { createAiUsageSettings, type AiUsageSettingsAdmin } from './use-cases/ai-usage-settings.js';
