import { describe, expect, it } from 'vitest';

import { createLog, reportingErrors } from './log.js';
import type { ErrorContext } from './ports.js';

describe('reportingErrors', () => {
  it('reports each error with only the fields a report may carry, and logs it as before', () => {
    const lines: string[] = [];
    const reported: { error: unknown; context: ErrorContext }[] = [];
    const log = reportingErrors(
      createLog((line) => lines.push(line)),
      {
        report: (error, context) => reported.push({ error, context }),
        flush: () => Promise.resolve(),
      },
    );
    const error = new Error('connect ECONNREFUSED');

    log.error('request failed', {
      method: 'GET',
      route: '/squads/:squadId',
      traceId: '105445aa7843bc8bf206b12000100000',
      member: '9b1f0c3e-1111-4222-8333-444455556666',
      error,
    });
    log.error('daily push not sent', { member: '9b1f0c3e-1111-4222-8333-444455556666' });
    log.warn('request refused', { route: '/me' });
    log.info('listening', { port: 8080 });

    expect(reported).toStrictEqual([
      {
        error,
        context: {
          message: 'request failed',
          method: 'GET',
          route: '/squads/:squadId',
          traceId: '105445aa7843bc8bf206b12000100000',
        },
      },
      {
        error: new Error('daily push not sent'),
        context: {
          message: 'daily push not sent',
          method: undefined,
          route: undefined,
          traceId: undefined,
        },
      },
    ]);
    expect(lines.map((line): unknown => JSON.parse(line))).toMatchObject([
      {
        severity: 'ERROR',
        message: 'request failed',
        member: '9b1f0c3e-1111-4222-8333-444455556666',
      },
      { severity: 'ERROR', message: 'daily push not sent' },
      { severity: 'WARNING', message: 'request refused' },
      { severity: 'INFO', message: 'listening' },
    ]);
  });
});
