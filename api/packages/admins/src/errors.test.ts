import { describe, expect, it } from 'vitest';

import { DemoAccountNotFoundError, NotAnAdminError } from './errors.js';

// Every error the admins module throws, so a changed reason or status shows up as a diff.
describe('admin errors', () => {
  it('each has its reason and status', () => {
    expect(
      [new NotAnAdminError(), new DemoAccountNotFoundError()].map(
        ({ name, reason, status, message }) => [name, reason, status, message],
      ),
    ).toStrictEqual([
      ['NotAnAdminError', 'NOT_AN_ADMIN', 'PERMISSION_DENIED', 'Only admins can use these tools.'],
      ['DemoAccountNotFoundError', 'DEMO_ACCOUNT_NOT_FOUND', 'NOT_FOUND', 'No such demo account.'],
    ]);
  });
});
