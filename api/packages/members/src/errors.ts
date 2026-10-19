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
