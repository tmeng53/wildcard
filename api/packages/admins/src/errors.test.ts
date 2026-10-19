import { describe, expect, it } from 'vitest';

import { NotAnAdminError } from './errors.js';

// Every error the admins module throws, so a changed reason or status shows up as a diff.
describe('admin errors', () => {
  it('each has its reason and status', () => {
    expect(
      [new NotAnAdminError()].map(({ name, reason, status, message }) => [
        name,
        reason,
        status,
        message,
      ]),
    ).toStrictEqual([
      ['NotAnAdminError', 'NOT_AN_ADMIN', 'PERMISSION_DENIED', 'Only admins can use these tools.'],
    ]);
  });
});
