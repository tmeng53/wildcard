import { describe, expect, it } from 'vitest';

import {
  CheckInDayMismatchError,
  CheckInIdConflictError,
  CheckInInTheFutureError,
  CheckInTooOldError,
  DisclaimerAlreadyPostedError,
  SquadNotJoinedError,
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
      ].map(({ name, reason, status }) => [name, reason, status]),
    ).toStrictEqual([
      ['CheckInIdConflictError', 'CHECK_IN_ID_CONFLICT', 'ALREADY_EXISTS'],
      ['DisclaimerAlreadyPostedError', 'DISCLAIMER_ALREADY_POSTED', 'ALREADY_EXISTS'],
      ['CheckInTooOldError', 'CHECK_IN_TOO_OLD', 'INVALID_ARGUMENT'],
      ['CheckInInTheFutureError', 'CHECK_IN_IN_THE_FUTURE', 'FAILED_PRECONDITION'],
      ['CheckInDayMismatchError', 'CHECK_IN_DAY_MISMATCH', 'INVALID_ARGUMENT'],
      ['SquadNotJoinedError', 'SQUAD_NOT_JOINED', 'PERMISSION_DENIED'],
    ]);
  });
});
