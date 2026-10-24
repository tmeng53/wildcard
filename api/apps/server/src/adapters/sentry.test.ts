import type { NodeOptions } from '@sentry/node';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { redactText } from '../log.js';
import { createSentryErrorReports } from './sentry.js';

const EnvelopeItem = z.tuple([
  z.looseObject({ type: z.string() }),
  z.record(z.string(), z.unknown()),
]);
type Envelope = Parameters<ReturnType<NonNullable<NodeOptions['transport']>>['send']>[0];

describe('createSentryErrorReports', () => {
  it('sends the error and its cause, masked as the log masks them, where it happened, and nothing about the member', async () => {
    const sent: Envelope[] = [];
    const reports = createSentryErrorReports({
      dsn: 'https://public@o1.ingest.us.sentry.io/2',
      release: 'wildcard-api-00042-abc',
      redact: redactText,
      // Sentry's servers are never called: the envelope is kept here instead.
      transport: () => ({
        send: (envelope) => {
          sent.push(envelope);
          return Promise.resolve({});
        },
        flush: () => Promise.resolve(true),
      }),
    });

    reports.report(
      new Error('squad 9b1f0c3e-1111-4222-8333-444455556666 vanished', {
        cause: new Error('auth failed for postgres://admin:hunter2@db.example.com:5432/postgres'),
      }),
      {
        message: 'request failed',
        method: 'GET',
        route: '/squads/:squadId',
        traceId: '105445aa7843bc8bf206b12000100000',
      },
    );
    await reports.flush(1000);

    const events = sent
      .flatMap(([, items]) => z.array(EnvelopeItem).parse(items))
      .filter(([header]) => header.type === 'event')
      .map(([, payload]) => payload);
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({
      release: 'wildcard-api-00042-abc',
      environment: 'production',
      tags: {
        log_message: 'request failed',
        method: 'GET',
        route: '/squads/:squadId',
        request_id: '105445aa7843bc8bf206b12000100000',
      },
      exception: {
        values: [
          {
            type: 'Error',
            value: 'auth failed for postgres://[credentials]@db.example.com:5432/postgres',
          },
          { type: 'Error', value: 'squad [id] vanished' },
        ],
      },
    });
    expect(events[0]).not.toHaveProperty('user');
    expect(events[0]).not.toHaveProperty('request');
    expect(events[0]?.breadcrumbs ?? []).toStrictEqual([]);
  });
});
