import { AppError } from '@wildcard/errors';

/**
 * Thrown when the caller isn't in the squad they name. The same answer whether or not the squad
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

/**
 * Thrown when a member without a current AI consent creates or joins a squad. The app asks for
 * it on the squad step and tries again. Drafts answer with the same reason.
 */
export class AiConsentRequiredError extends AppError {
  override readonly name = 'AiConsentRequiredError';
  readonly reason = 'AI_CONSENT_REQUIRED';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('Agree to the AI terms before joining or making a squad.');
  }
}

/** Thrown for an invite code no squad has: a typo, or a link from somewhere else. */
export class InviteCodeUnknownError extends AppError {
  override readonly name = 'InviteCodeUnknownError';
  readonly reason = 'INVITE_CODE_UNKNOWN';
  readonly status = 'NOT_FOUND';

  constructor() {
    super('No squad has this invite code.');
  }
}

/** Thrown when joining a squad that already has 8 members. */
export class SquadFullError extends AppError {
  override readonly name = 'SquadFullError';
  readonly reason = 'SQUAD_FULL';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly limit: number) {
    super(`This squad already has ${String(limit)} members.`);
  }
}

/** Thrown when a member in 3 squads creates or joins another. Leave one first. */
export class SquadLimitReachedError extends AppError {
  override readonly name = 'SquadLimitReachedError';
  readonly reason = 'SQUAD_LIMIT_REACHED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(readonly limit: number) {
    super(`You are already in ${String(limit)} squads. Leave one to join another.`);
  }
}

/**
 * Thrown when a squad id is already taken by another member's squad or a different name. The app
 * made a new squad with an old id: give it a new id.
 */
export class SquadIdConflictError extends AppError {
  override readonly name = 'SquadIdConflictError';
  readonly reason = 'SQUAD_ID_CONFLICT';
  readonly status = 'ALREADY_EXISTS';

  constructor(readonly squadId: string) {
    super(`Squad ${squadId} already exists.`);
  }
}
