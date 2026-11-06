import type { Campaign, CampaignId, CampaignStatus } from '../domain/campaigns.js';
import { CampaignNotFoundError } from '../errors.js';
import type { CampaignStore } from '../ports.js';

/** The campaigns, for admins: what each bundles and how far along it is. */
export interface Campaigns {
  list(): Promise<readonly Campaign[]>;
  find(id: CampaignId): Promise<Campaign | undefined>;
  /**
   * Adds a campaign as a draft, or changes one's label and switches, keeping its status.
   * Answers with the campaign now.
   */
  put(change: {
    readonly id: CampaignId;
    readonly label: string;
    readonly switches: readonly string[];
    readonly by: string;
  }): Promise<Campaign>;
  /** Moves a campaign to `status`; answers with it now. */
  move(change: {
    readonly id: CampaignId;
    readonly status: CampaignStatus;
    readonly by: string;
  }): Promise<Campaign>;
}

export function createCampaigns({ store }: { readonly store: CampaignStore }): Campaigns {
  const find = async (id: CampaignId) => (await store.list()).find((each) => each.id === id);
  const save = async ({
    id,
    by,
    ...value
  }: Omit<Campaign, 'changedAt'> & { readonly by: string }) => {
    await store.put({
      id,
      value: {
        version: 1,
        label: value.label,
        status: value.status,
        switches: [...value.switches],
      },
      by,
    });
    const now = await find(id);
    if (now === undefined) throw new CampaignNotFoundError(id);
    return now;
  };
  return {
    list: () => store.list(),
    find,
    async put({ id, label, switches, by }) {
      const current = await find(id);
      return save({ id, by, label, switches: [...switches], status: current?.status ?? 'draft' });
    },
    async move({ id, status, by }) {
      const current = await find(id);
      if (current === undefined) throw new CampaignNotFoundError(id);
      return save({ ...current, status, by });
    },
  };
}
