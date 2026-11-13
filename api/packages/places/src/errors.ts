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

/** Thrown when a place id is already a place with other contents, or another squad's. */
export class SquadPlaceIdConflictError extends AppError {
  override readonly name = 'SquadPlaceIdConflictError';
  readonly reason = 'SQUAD_PLACE_ID_CONFLICT';
  readonly status = 'ALREADY_EXISTS';

  constructor(readonly id: string) {
    super(`Place ${id} was already added with different contents.`);
  }
}
