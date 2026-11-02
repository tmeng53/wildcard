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
