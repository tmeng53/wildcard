import { describe, expect, it } from 'vitest';

import { PushRejectedError, PushUnavailableError } from './errors.js';

// Every error the push module throws, so a changed reason or status shows up as a diff.
describe('push errors', () => {
  it('each has its reason and status', () => {
    expect(
      [new PushRejectedError(403, 'InvalidProviderToken'), new PushUnavailableError()].map(
        ({ name, reason, status }) => [name, reason, status],
      ),
    ).toStrictEqual([
      ['PushRejectedError', 'PUSH_REJECTED', 'INTERNAL'],
      ['PushUnavailableError', 'PUSH_UNAVAILABLE', 'UNAVAILABLE'],
    ]);
  });
});
