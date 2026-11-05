// @wildcard/campaigns: what an admin bundles for a holiday or any other moment (the switches it
// owns, which its status turns on for previewers, everyone or nobody), kept in the database so
// an event is data, never a concept in code.

export {
  createPostgresCampaignStore,
  type CampaignTables,
} from './adapters/postgres-campaign-store.js';
export {
  CAMPAIGN_STATUSES,
  CampaignId,
  CampaignStatus,
  CampaignValue,
  SWITCH_MODE_OF,
  type Campaign,
} from './domain/campaigns.js';
export { CampaignNotFoundError, CampaignSwitchTakenError } from './errors.js';
export type { CampaignStore } from './ports.js';
export { createCampaigns, type Campaigns } from './use-cases/campaigns.js';
