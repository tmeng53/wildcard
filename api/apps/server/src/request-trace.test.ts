import { Hono } from 'hono';
import { routePath } from 'hono/route';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createLog } from './log.js';
import { requestTrace, traceOf } from './request-trace.js';

const Entry = z.record(z.string(), z.unknown());

const traceId = '105445aa7843bc8bf206b12000100000';

describe('traceOf', () => {
  it('reads Google’s header, with its decimal span as 16 hex digits', () => {
    expect(traceOf(`${traceId}/74;o=1`, undefined)).toStrictEqual({
      traceId,
      spanId: '000000000000004a',
    });
    expect(traceOf(traceId.toUpperCase(), undefined)).toStrictEqual({ traceId, spanId: undefined });
  });

  it('falls back to W3C traceparent', () => {
    expect(traceOf(undefined, `00-${traceId}-00f067aa0ba902b7-01`)).toStrictEqual({
      traceId,
      spanId: '00f067aa0ba902b7',
    });
  });

  it('makes up an id for a request with no trace, or one that isn’t a trace', () => {
    for (const [google, w3c] of [
      [undefined, undefined],
      ['"><script>', 'not-a-trace'],
      [`${'0'.repeat(32)}/1`, undefined],
    ] as const) {
      const { traceId: made, spanId } = traceOf(google, w3c);
      expect(made).toMatch(/^[0-9a-f]{32}$/);
      expect(made).not.toBe('0'.repeat(32));
      expect(spanId).toBeUndefined();
    }
  });
});

describe('requestTrace', () => {
  function appLogging() {
    const logged: Record<string, unknown>[] = [];
    const log = createLog((line) => logged.push(Entry.parse(JSON.parse(line))), {
      traceProject: 'wildcard-test',
    });
    const app = new Hono();
    app.use(requestTrace());
    app.get('/squads/:squadId', async (c) => {
      await Promise.resolve();
      log.info('deep in a route');
      return c.text('ok');
    });
    app.get('/fails/:id', () => {
      throw new Error('boom');
    });
    app.onError((error, c) => {
      log.error('request failed', { route: routePath(c), error });
      return c.text('down', 500);
    });
    return { app, logged };
  }

  it('puts the trace on every entry a request logs, and its id on the response', async () => {
    const { app, logged } = appLogging();
    const response = await app.request('/squads/x', {
      headers: { 'X-Cloud-Trace-Context': `${traceId}/74;o=1` },
    });
    expect(response.headers.get('X-Request-Id')).toBe(traceId);
    expect(logged).toStrictEqual([
      {
        severity: 'INFO',
        message: 'deep in a route',
        requestId: traceId,
        'logging.googleapis.com/trace': `projects/wildcard-test/traces/${traceId}`,
        'logging.googleapis.com/spanId': '000000000000004a',
      },
    ]);
  });

  it('names a failed request by its route, and sends the id with the failure too', async () => {
    const { app, logged } = appLogging();
    const response = await app.request('/fails/secret-invite-code', {
      headers: { 'X-Cloud-Trace-Context': traceId },
    });
    expect([response.status, response.headers.get('X-Request-Id')]).toStrictEqual([500, traceId]);
    expect(logged[0]).toMatchObject({
      severity: 'ERROR',
      route: '/fails/:id',
      requestId: traceId,
      'logging.googleapis.com/trace': `projects/wildcard-test/traces/${traceId}`,
    });
    expect(JSON.stringify(logged)).not.toContain('secret-invite-code');
  });
});
