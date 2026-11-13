import { AppError } from '@wildcard/errors';

/** Thrown when a signed-in member who isn't on the admin list asks for an admin tool. */
export class NotAnAdminError extends AppError {
  override readonly name = 'NotAnAdminError';
  readonly reason = 'NOT_AN_ADMIN';
  readonly status = 'PERMISSION_DENIED';

  constructor() {
    super('Only admins can use these tools.');
  }
}

/** Thrown when an admin asks for a demo account that isn't one of theirs. */
export class DemoAccountNotFoundError extends AppError {
  override readonly name = 'DemoAccountNotFoundError';
  readonly reason = 'DEMO_ACCOUNT_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor() {
    super('No such demo account.');
  }
}
