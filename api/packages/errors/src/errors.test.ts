import { describe, expect, it } from 'vitest';

import { AppError, hasErrorCode, toProblemDetails } from './errors.js';

class DocumentChangedError extends AppError {
  override readonly name = 'DocumentChangedError';
  readonly reason = 'DOCUMENT_CHANGED';
  readonly status = 'ABORTED';

  constructor(readonly documentId: string) {
    super(`Document ${documentId} changed since it was read`);
  }
}

describe('toProblemDetails', () => {
  it('describes one of our errors with its reason, status and message', () => {
    expect(toProblemDetails(new DocumentChangedError('d1'))).toStrictEqual({
      type: 'about:blank',
      title: 'Conflict',
      status: 409,
      detail: 'Document d1 changed since it was read',
      reason: 'DOCUMENT_CHANGED',
      errorStatus: 'ABORTED',
    });
  });

  it('answers anything else as INTERNAL without its message', () => {
    expect(toProblemDetails(new Error('relation "users" does not exist'))).toStrictEqual({
      type: 'about:blank',
      title: 'Internal Server Error',
      status: 500,
      detail: 'Something went wrong on our side.',
      reason: 'INTERNAL',
      errorStatus: 'INTERNAL',
    });
  });
});

describe('hasErrorCode', () => {
  it('matches the code a library error carries', () => {
    const error = Object.assign(new Error('connect ECONNREFUSED'), { code: 'ECONNREFUSED' });
    expect([hasErrorCode(error, 'ECONNREFUSED'), hasErrorCode(error, '23505')]).toStrictEqual([
      true,
      false,
    ]);
  });
});
