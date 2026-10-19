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
