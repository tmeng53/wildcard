import { AppError } from '@wildcard/errors';

/** Thrown when a campaign's id names none. */
export class CampaignNotFoundError extends AppError {
  override readonly name = 'CampaignNotFoundError';
  readonly reason = 'CAMPAIGN_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly campaign: string) {
    super(`There is no campaign ${campaign}.`);
  }
}
