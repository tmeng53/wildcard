import { generateKeyPairSync, verify } from 'node:crypto';
import { createServer, type IncomingHttpHeaders } from 'node:http2';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { DeviceToken, type Device } from '../domain/device.js';
import type { PushNotification } from '../domain/notification.js';
import { PushRejectedError, PushUnavailableError } from '../errors.js';
import { createApnsSender } from './apns-sender.js';

// A local HTTP/2 server stands in for Apple's: it records each request and answers as a test
// says, so the sender's real HTTP/2, headers, JWT and payload are what's checked.
interface Received {
  readonly headers: IncomingHttpHeaders;
  readonly body: string;
}
const received: Received[] = [];
let answer: { status: number; body?: string } = { status: 200 };
const server = createServer((request, response) => {
  let body = '';
  request.setEncoding('utf8');
  request.on('data', (chunk: string) => {
    body += chunk;
  });
  request.on('end', () => {
    received.push({ headers: request.headers, body });
    response.writeHead(answer.status, { 'apns-id': 'test' });
    response.end(answer.body ?? '');
  });
});
let origin = '';
beforeAll(async () => {
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = z.object({ port: z.int() }).parse(server.address());
  origin = `http://127.0.0.1:${String(port)}`;
});
afterAll(
  () =>
    new Promise<void>((resolve) =>
      server.close(() => {
        resolve();
      }),
    ),
);

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const key = {
  keyId: 'ABC123DEFG',
  teamId: 'TEAM123456',
  privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
  topic: 'com.wildcardsquad.wildcard',
};
let clock = Date.parse('2026-10-19T05:00:00.000Z');
function senderFor() {
  return createApnsSender(key, {
    origins: { sandbox: origin, production: origin },
    now: () => clock,
  });
}

const device: Device = {
  token: DeviceToken.parse('a1'.repeat(32)),
  environment: 'production',
};
const reaction: PushNotification = {
  alert: { key: 'push.reaction.cheer', args: ['3'] },
  category: 'reaction',
  thread: 'check-in:1',
  collapseId: 'reactions:1',
  interruption: 'active',
  event: { checkIn: '1' },
};

const Jwt = z.tuple([z.string(), z.string(), z.string()]);
const decode = (part: string): unknown => JSON.parse(Buffer.from(part, 'base64url').toString());

describe('the APNs sender', () => {
  it('posts the notification to the device with a signed provider token', async () => {
    received.length = 0;
    answer = { status: 200 };
    const apns = senderFor();
    expect(await apns.send(device, reaction)).toBe('sent');
    apns.close();

    const [request] = received;
    expect(request?.headers[':method']).toBe('POST');
    expect(request?.headers[':path']).toBe(`/3/device/${'a1'.repeat(32)}`);
    expect(request?.headers['apns-topic']).toBe('com.wildcardsquad.wildcard');
    expect(request?.headers['apns-push-type']).toBe('alert');
    expect(request?.headers['apns-priority']).toBe('10');
    expect(request?.headers['apns-collapse-id']).toBe('reactions:1');
    expect(JSON.parse(request?.body ?? '')).toStrictEqual({
      version: 1,
      aps: {
        alert: { 'loc-key': 'push.reaction.cheer', 'loc-args': ['3'] },
        category: 'reaction',
        'thread-id': 'check-in:1',
        'interruption-level': 'active',
        sound: 'default',
      },
      event: { checkIn: '1' },
    });

    const authorization = z.string().parse(request?.headers.authorization);
    const [header, claims, signature] = Jwt.parse(authorization.replace(/^bearer /, '').split('.'));
    expect(decode(header)).toStrictEqual({ alg: 'ES256', kid: 'ABC123DEFG' });
    expect(decode(claims)).toStrictEqual({ iss: 'TEAM123456', iat: 1_792_386_000 });
    expect(
      verify(
        'sha256',
        Buffer.from(`${header}.${claims}`),
        { key: publicKey, dsaEncoding: 'ieee-p1363' },
        Buffer.from(signature, 'base64url'),
      ),
    ).toBe(true);
  });

  it('sends a quiet notification at low priority, with no sound and no collapse id', async () => {
    received.length = 0;
    answer = { status: 200 };
    const apns = senderFor();
    const { alert, category, thread, event } = reaction;
    const quiet = { alert, category, thread, event, interruption: 'passive' as const };
    expect(await apns.send(device, quiet)).toBe('sent');
    apns.close();
    const [request] = received;
    expect(request?.headers['apns-priority']).toBe('5');
    expect(request?.headers['apns-collapse-id']).toBeUndefined();
    expect(
      z.looseObject({ aps: z.looseObject({}) }).parse(JSON.parse(request?.body ?? '')).aps,
    ).toStrictEqual({
      alert: { 'loc-key': 'push.reaction.cheer', 'loc-args': ['3'] },
      category: 'reaction',
      'thread-id': 'check-in:1',
      'interruption-level': 'passive',
    });
  });

  it('reuses its provider token for 50 minutes, then signs a new one', async () => {
    received.length = 0;
    answer = { status: 200 };
    clock = Date.parse('2026-10-19T05:00:00.000Z');
    const apns = senderFor();
    await apns.send(device, reaction);
    clock += 49 * 60 * 1000;
    await apns.send(device, reaction);
    clock += 60 * 1000;
    await apns.send(device, reaction);
    apns.close();
    const [first, second, third] = received.map((request) => request.headers.authorization);
    expect(second).toBe(first);
    expect(third).not.toBe(first);
  });

  it.each([
    { status: 410, reason: 'Unregistered' },
    { status: 400, reason: 'BadDeviceToken' },
    { status: 410, reason: 'ExpiredToken' },
  ])('says a device is gone on $status $reason', async ({ status, reason }) => {
    answer = { status, body: JSON.stringify({ reason }) };
    const apns = senderFor();
    expect(await apns.send(device, reaction)).toBe('gone');
    apns.close();
  });

  it('keeps the device when the token is for another topic: that is our setting, not the phone', async () => {
    answer = { status: 400, body: JSON.stringify({ reason: 'DeviceTokenNotForTopic' }) };
    const apns = senderFor();
    await expect(apns.send(device, reaction)).rejects.toStrictEqual(
      new PushRejectedError(400, 'DeviceTokenNotForTopic'),
    );
    apns.close();
  });

  it.each([
    { status: 429, reason: 'TooManyRequests' },
    { status: 500, reason: 'InternalServerError' },
    { status: 503, reason: 'ServiceUnavailable' },
  ])(
    'says the service is unavailable on $status $reason, which Apple says to retry',
    async ({ status, reason }) => {
      answer = { status, body: JSON.stringify({ reason }) };
      const apns = senderFor();
      await expect(apns.send(device, reaction)).rejects.toBeInstanceOf(PushUnavailableError);
      apns.close();
    },
  );

  it('throws Apple’s reason for any other refusal', async () => {
    answer = { status: 403, body: JSON.stringify({ reason: 'InvalidProviderToken' }) };
    const apns = senderFor();
    await expect(apns.send(device, reaction)).rejects.toStrictEqual(
      new PushRejectedError(403, 'InvalidProviderToken'),
    );
    apns.close();
  });

  it('throws when Apple can’t be reached', async () => {
    // Nothing listens on port 1.
    const apns = createApnsSender(key, {
      origins: { sandbox: 'http://127.0.0.1:1', production: 'http://127.0.0.1:1' },
    });
    await expect(apns.send(device, reaction)).rejects.toBeInstanceOf(PushUnavailableError);
    apns.close();
  });
});
