import type { Kysely } from 'kysely';

import { CampaignId, CampaignValue, type Campaign } from '../domain/campaigns.js';
import type { CampaignStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads, as generated from the migrations. */
export type CampaignTables = DB;

/**
 * The campaigns on Postgres (`supabase/migrations`, `campaigns`): one row per change, never
 * changed, the newest per id being the campaign now. A change runs in the caller's transaction
 * when `db` is one.
 */
export function createPostgresCampaignStore(db: Kysely<CampaignTables>): CampaignStore {
  const list = async (): Promise<Campaign[]> => {
    const rows = await db
      .selectFrom('campaigns as e')
      .select(['e.campaign_id', 'e.value', 'e.at'])
      .where((eb) =>
        eb.not(
          eb.exists(
            eb
              .selectFrom('campaigns as newer')
              .select('newer.id')
              .whereRef('newer.campaign_id', '=', 'e.campaign_id')
              .whereRef('newer.id', '>', 'e.id'),
          ),
        ),
      )
      .orderBy('e.id', 'desc')
      .execute();
    return rows.map((row) => {
      const { label, status, switches } = CampaignValue.parse(row.value);
      return {
        id: CampaignId.parse(row.campaign_id),
        label,
        status,
        switches,
        changedAt: new Date(row.at),
      };
    });
  };
  return {
    list,
    async put({ id, value, by }) {
      const now = (await list()).find((each) => each.id === id);
      if (
        now?.label === value.label &&
        now.status === value.status &&
        JSON.stringify(now.switches) === JSON.stringify(value.switches)
      )
        return { changed: false };
      await db
        .insertInto('campaigns')
        .values({ campaign_id: id, value: JSON.stringify(value), changed_by: by })
        .execute();
      return { changed: true };
    },
  };
}
