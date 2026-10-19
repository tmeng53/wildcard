import { describe, expect, it } from 'vitest';

import {
  CheckInDayMismatchError,
  CheckInIdConflictError,
  CheckInInTheFutureError,
  CheckInNotFoundError,
  CheckInTooOldError,
  DisclaimerAlreadyPostedError,
  OwnCheckInReactionError,
  PlanDayStartedError,
  RestDaysFixedError,
  SquadNotJoinedError,
  TimeZoneNotSetError,
  WeekOverError,
  WeekTooFarAheadError,
} from './errors.js';

// Every error the check-ins module throws, so a changed reason or status shows up as a diff.
describe('check-in errors', () => {
  it('each has its reason and status', () => {
    expect(
      [
        new CheckInIdConflictError('c1'),
        new DisclaimerAlreadyPostedError('2026-10-18'),
        new CheckInTooOldError(),
        new CheckInInTheFutureError(),
        new CheckInDayMismatchError('2026-10-18'),
        new SquadNotJoinedError('s1'),
        new WeekOverError('2026-10-12'),
        new WeekTooFarAheadError('2027-01-04'),
        new PlanDayStartedError('2026-10-19'),
        new RestDaysFixedError(2),
        new TimeZoneNotSetError(),
        new CheckInNotFoundError('c1'),
        new OwnCheckInReactionError(),
      ].map(({ name, reason, status }) => [name, reason, status]),
    ).toStrictEqual([
      ['CheckInIdConflictError', 'CHECK_IN_ID_CONFLICT', 'ALREADY_EXISTS'],
      ['DisclaimerAlreadyPostedError', 'DISCLAIMER_ALREADY_POSTED', 'ALREADY_EXISTS'],
      ['CheckInTooOldError', 'CHECK_IN_TOO_OLD', 'INVALID_ARGUMENT'],
      ['CheckInInTheFutureError', 'CHECK_IN_IN_THE_FUTURE', 'FAILED_PRECONDITION'],
      ['CheckInDayMismatchError', 'CHECK_IN_DAY_MISMATCH', 'INVALID_ARGUMENT'],
      ['SquadNotJoinedError', 'SQUAD_NOT_JOINED', 'PERMISSION_DENIED'],
      ['WeekOverError', 'WEEK_OVER', 'FAILED_PRECONDITION'],
      ['WeekTooFarAheadError', 'WEEK_TOO_FAR_AHEAD', 'INVALID_ARGUMENT'],
      ['PlanDayStartedError', 'PLAN_DAY_STARTED', 'FAILED_PRECONDITION'],
      ['RestDaysFixedError', 'REST_DAYS_FIXED', 'FAILED_PRECONDITION'],
      ['TimeZoneNotSetError', 'TIME_ZONE_NOT_SET', 'FAILED_PRECONDITION'],
      ['CheckInNotFoundError', 'CHECK_IN_NOT_FOUND', 'NOT_FOUND'],
      ['OwnCheckInReactionError', 'OWN_CHECK_IN_REACTION', 'FAILED_PRECONDITION'],
    ]);
  });
});
