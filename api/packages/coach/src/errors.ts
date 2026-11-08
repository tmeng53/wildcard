import { AppError } from '@wildcard/errors';

/** Thrown when a squad hires a coach that isn't offered (retired) or doesn't exist. */
export class CoachNotOfferedError extends AppError {
  override readonly name = 'CoachNotOfferedError';
  readonly reason = 'COACH_NOT_OFFERED';
  readonly status = 'FAILED_PRECONDITION';

  constructor(coach: string) {
    super(`No coach ${coach} is offered.`);
  }
}

/** Thrown when a squad that has a coach hires another: it fires its coach first. */
export class CoachAlreadyHiredError extends AppError {
  override readonly name = 'CoachAlreadyHiredError';
  readonly reason = 'COACH_ALREADY_HIRED';
  readonly status = 'ALREADY_EXISTS';

  constructor(coach: string) {
    super(`The squad has hired ${coach} already; fire it first.`);
  }
}

/** Thrown when a squad with no coach fires one. */
export class NoCoachHiredError extends AppError {
  override readonly name = 'NoCoachHiredError';
  readonly reason = 'NO_COACH_HIRED';
  readonly status = 'FAILED_PRECONDITION';

  constructor() {
    super('The squad has no coach to fire.');
  }
}

/** Thrown when a coach is hired for a squad that doesn't exist (or has ended). */
export class CoachSquadNotFoundError extends AppError {
  override readonly name = 'CoachSquadNotFoundError';
  readonly reason = 'COACH_SQUAD_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor() {
    super('No such squad.');
  }
}

/** Thrown when an admin writes a coach memory page for someone who has no account. */
export class CoachFileMemberNotFoundError extends AppError {
  override readonly name = 'CoachFileMemberNotFoundError';
  readonly reason = 'COACH_FILE_MEMBER_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor() {
    super('No member with that id: a page is people/<member id>.md.');
  }
}

/** Thrown when a member puts away a morning note that isn't theirs in that squad, or isn't there. */
export class CoachNoteNotFoundError extends AppError {
  override readonly name = 'CoachNoteNotFoundError';
  readonly reason = 'COACH_NOTE_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor() {
    super('No such morning note for the member in this squad.');
  }
}
