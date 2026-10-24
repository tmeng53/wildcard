import { AppError } from '@wildcard/errors';

/**
 * Thrown when the caller isn't in a squad they name. The same answer whether or not the squad
 * exists, so it reveals nothing about other squads. The reason is the one check-ins answer with.
 */
export class SquadNotJoinedError extends AppError {
  override readonly name = 'SquadNotJoinedError';
  readonly reason = 'SQUAD_NOT_JOINED';
  readonly status = 'PERMISSION_DENIED';

  constructor(readonly squadId: string) {
    super(`You aren’t in squad ${squadId}.`);
  }
}

/** Thrown when the member to nudge isn't in the squad (any more): the app reloads the squad. */
export class NotASquadmateError extends AppError {
  override readonly name = 'NotASquadmateError';
  readonly reason = 'NOT_A_SQUADMATE';
  readonly status = 'NOT_FOUND';

  constructor(readonly member: string) {
    super(`Member ${member} isn’t in this squad.`);
  }
}

/** Thrown when a member nudges themselves. */
export class OwnNudgeError extends AppError {
  override readonly name = 'OwnNudgeError';
  readonly reason = 'OWN_NUDGE';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('You can’t nudge yourself.');
  }
}
