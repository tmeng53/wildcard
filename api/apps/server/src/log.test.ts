import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createLog, inRequest, logAlso } from './log.js';

const Entry = z.record(z.string(), z.unknown());

function capture(traceProject?: string) {
  const logged: Record<string, unknown>[] = [];
  const log = createLog((line) => logged.push(Entry.parse(JSON.parse(line))), {
    traceProject,
  });
  return { log, logged };
}

const member = '3f0c5f8e-1b2a-4c3d-8e9f-0a1b2c3d4e5f';
const photo = `${member}/9d8c7b6a-5f4e-4d3c-b2a1-0f9e8d7c6b5a`;

describe('createLog', () => {
  it('writes an entry outside a request with no trace', () => {
    const { log, logged } = capture('wildcard-test');
    log.info('listening', { port: 8080 });
    expect(logged).toStrictEqual([{ severity: 'INFO', message: 'listening', port: 8080 }]);
  });

  it('names the request’s trace and span, and what the request added, on every entry in it', async () => {
    const { log, logged } = capture('wildcard-test');
    const traceId = '105445aa7843bc8bf206b12000100000';
    await inRequest({ traceId, spanId: '000000000000004a' }, async () => {
      logAlso({ member });
      await Promise.resolve();
      log.warn('request refused', { status: 404 });
    });
    log.info('after');
    expect(logged).toStrictEqual([
      {
        severity: 'WARNING',
        message: 'request refused',
        member,
        status: 404,
        requestId: traceId,
        'logging.googleapis.com/trace': `projects/wildcard-test/traces/${traceId}`,
        'logging.googleapis.com/spanId': '000000000000004a',
      },
      { severity: 'INFO', message: 'after' },
    ]);
  });

  it('gives only the request id off Google Cloud', () => {
    const { log, logged } = capture();
    inRequest({ traceId: 'a'.repeat(32), spanId: undefined }, () => {
      log.info('hello');
    });
    expect(logged).toStrictEqual([
      { severity: 'INFO', message: 'hello', requestId: 'a'.repeat(32) },
    ]);
  });

  it('writes an error’s stack where Error Reporting finds it', () => {
    const { log, logged } = capture();
    const error = new Error('boom');
    log.error('request failed', { error });
    expect(logged[0]).toMatchObject({
      severity: 'ERROR',
      error: { name: 'Error', message: 'boom', stack: error.stack },
      stack_trace: error.stack,
    });
  });

  it('never writes what people typed, tokens, emails, keys, photo paths or device tokens', () => {
    const { log, logged } = capture();
    const jwt = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJl';
    const device = 'ab'.repeat(32);
    log.error('request failed', {
      member,
      caption: '今天练腿了',
      body: { caption: 'x', photos: [{ path: photo }] },
      headers: { Authorization: `Bearer ${jwt}` },
      note: `sent to tracy@example.com with ${jwt}, key sb_secret_abc123 and sk-proj-abcdefghijklmnopqrst`,
      error: new Error(`could not read ${photo} for ${device}`),
      cause: 'connect to postgres://postgres:p4ss!w0rd@db.example.com:6543/postgres failed',
    });
    const [entry] = logged;
    expect(entry).toMatchObject({
      member,
      caption: '[redacted]',
      body: '[redacted]',
      headers: { Authorization: '[redacted]' },
      note: 'sent to [email] with [token], key [key] and [key]',
      error: { message: 'could not read [photo] for [device]' },
      cause: 'connect to postgres://[credentials]@db.example.com:6543/postgres failed',
    });
    const line = JSON.stringify(entry);
    for (const secret of [
      '今天练腿了',
      jwt,
      'tracy@example.com',
      'sb_secret_abc123',
      'p4ss!w0rd',
      photo,
      device,
    ]) {
      expect(line).not.toContain(secret);
    }
  });
});
