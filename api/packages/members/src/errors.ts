import { AppError } from '@wildcard/errors';

/** Thrown for a time zone name that isn't a known zone. The app sends the phone's own zone. */
export class TimeZoneUnknownError extends AppError {
  override readonly name = 'TimeZoneUnknownError';
  readonly reason = 'TIME_ZONE_UNKNOWN';
  readonly status = 'INVALID_ARGUMENT';

  constructor(readonly timeZone: string) {
    super(`${timeZone} is not a known time zone.`);
  }
}

/** Thrown for a change to a profile the member hasn't saved yet (they save it right after signing up). */
export class ProfileMissingError extends AppError {
  override readonly name = 'ProfileMissingError';
  readonly reason = 'PROFILE_MISSING';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('The member has no profile yet.');
  }
}
