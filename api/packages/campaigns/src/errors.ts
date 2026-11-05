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

/** Thrown when a campaign names a switch that is already there and not its own. */
export class CampaignSwitchTakenError extends AppError {
  override readonly name = 'CampaignSwitchTakenError';
  readonly reason = 'CAMPAIGN_SWITCH_TAKEN';
  readonly status = 'FAILED_PRECONDITION';

  constructor(
    readonly campaign: string,
    readonly switchId: string,
  ) {
    super(
      `The switch ${switchId} is already there and not campaign ${campaign}’s: a campaign owns ` +
        'only switches it made, so give it a new id.',
    );
  }
}
