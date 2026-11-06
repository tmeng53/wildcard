import type { Campaign, CampaignValue } from './domain/campaigns.js';

/** Where the campaigns are kept: one row per change, the newest per id being the campaign now. */
export interface CampaignStore {
  /** Every campaign as it is now, newest change first. */
  list(): Promise<Campaign[]>;
  /** Appends `value` as campaign `id` now, by `by`; nothing when it is what `id` already says. */
  put(change: {
    readonly id: string;
    readonly value: CampaignValue;
    readonly by: string;
  }): Promise<{ readonly changed: boolean }>;
}
