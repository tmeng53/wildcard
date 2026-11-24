import { AppError } from '@wildcard/errors';

/** Thrown when a member blocks themselves. */
export class BlockSelfError extends AppError {
  override readonly name = 'BlockSelfError';
  readonly reason = 'BLOCK_SELF';
  readonly status = 'INVALID_ARGUMENT';

  constructor() {
    super('A member can’t block themselves.');
  }
}

/** Thrown when a report's id is another member's report. */
export class ReportIdTakenError extends AppError {
  override readonly name = 'ReportIdTakenError';
  readonly reason = 'REPORT_ID_TAKEN';
  readonly status = 'ALREADY_EXISTS';

  constructor(readonly id: string) {
    super(`Report ${id} already exists.`);
  }
}

/** Thrown when blocking someone who isn't a member (no profile). */
export class BlockedMemberMissingError extends AppError {
  override readonly name = 'BlockedMemberMissingError';
  readonly reason = 'MEMBER_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly member: string) {
    super(`There is no member ${member}.`);
  }
}

/** Thrown when what is reported isn't there, or isn't something the reporter can see. */
export class ReportedItemMissingError extends AppError {
  override readonly name = 'ReportedItemMissingError';
  readonly reason = 'REPORTED_ITEM_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly item: string) {
    super(`There is nothing ${item} you can see to report.`);
  }
}
