import { z } from 'zod';

// Campaigns (Tracy, 2026-11-04): a holiday, an anniversary or a race day is never a concept in
// code. An admin bundles the generic pieces (global switches with their windows, and the scenes,
// unlock rules and broadcast notices that follow them), tries it on their own phone, then
// publishes it. A campaign only names the switches it owns and how far along it is: its status
// sets their mode. Kept in the database (supabase/migrations, `campaigns`).

/** A campaign's id, camelCase, such as `thanksgiving`. Never changes. */
export const CampaignId = z.string().regex(/^[a-z][A-Za-z0-9]{0,39}$/);
export type CampaignId = z.infer<typeof CampaignId>;

export const CAMPAIGN_STATUSES = ['draft', 'preview', 'live', 'stopped'] as const;
export const CampaignStatus = z.enum(CAMPAIGN_STATUSES);
export type CampaignStatus = z.infer<typeof CampaignStatus>;

/** A campaign as it is stored: a top-level `version`, like every stored JSON. */
export const CampaignValue = z.strictObject({
  version: z.literal(1),
  label: z.string().trim().min(1).max(80),
  status: CampaignStatus,
  /** The switches it owns, which its status turns on or off. */
  switches: z.array(z.string().regex(/^[a-z][A-Za-z0-9]{0,39}$/)).max(10),
});
export type CampaignValue = z.infer<typeof CampaignValue>;

export interface Campaign extends Omit<CampaignValue, 'version'> {
  readonly id: CampaignId;
  readonly changedAt: Date;
}

/** The mode a campaign's switches take in each status. */
export const SWITCH_MODE_OF: Record<CampaignStatus, 'off' | 'preview' | 'schedule'> = {
  // Only the admin's preview list sees it, on the day they pretend it is.
  preview: 'preview',
  // Everyone, on its days.
  live: 'schedule',
  // Nobody.
  draft: 'off',
  stopped: 'off',
};
