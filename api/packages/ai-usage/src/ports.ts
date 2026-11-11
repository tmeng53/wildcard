import type { TokenUsage } from '@wildcard/language-model';

import type { AiUsageSettings, MemberId } from './domain/settings.js';
import type { AiFeature, ModelName, UsageTotal } from './domain/usage.js';

/** Where the settings are kept: one value, and a log of every change to it. */
export interface AiUsageSettingsStore {
  /**
   * The settings now. `forUpdate` holds the row until the caller's transaction ends, so two
   * admins changing them at once apply one change after the other.
   */
  current(options?: { readonly forUpdate?: boolean }): Promise<AiUsageSettings>;
  /**
   * Saves `settings` with `by` as who changed them, unless they are the settings already: then
   * nothing is saved or logged. Says whether anything changed.
   */
  save(settings: AiUsageSettings, by: MemberId): Promise<boolean>;
}

/** One model call, as the ledger keeps it. */
export interface UsageEntry {
  readonly feature: AiFeature;
  readonly squad: string | undefined;
  readonly member: string | undefined;
  readonly model: ModelName;
  readonly usage: TokenUsage;
  readonly costMicros: number;
  readonly at: Date;
}

/** Every model call, append-only. */
export interface AiUsageLedger {
  record(entry: UsageEntry): Promise<void>;
  /** What was spent since `since`, in US dollars' millionths: for this squad, or by everyone. */
  spent(input: { readonly squad?: string; readonly since: Date }): Promise<number>;
  /** A squad's calls for these features, since `since` or ever. */
  total(input: {
    readonly squad: string;
    readonly features: readonly AiFeature[];
    readonly since?: Date;
  }): Promise<UsageTotal>;
}

/** Each squad's time zone (小队时区) at a moment: its day is the day its cap counts over. */
export type SquadTimeZones = (
  squads: readonly string[],
  at: Date,
) => Promise<(squad: string) => string>;

/** The squad a member is in now, if any: a call for them is counted to it. */
export type SquadOf = (member: string) => Promise<string | undefined>;

/** The current time. */
export type Clock = () => Date;
