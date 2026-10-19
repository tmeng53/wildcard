import { createPrivateKey, sign, type KeyObject } from 'node:crypto';
import { connect, constants, type ClientHttp2Session } from 'node:http2';

import { z } from 'zod';

import type { PushEnvironment } from '../domain/device.js';
import { apnsPayload } from '../domain/notification.js';
import { PushRejectedError, PushUnavailableError } from '../errors.js';
import type { PushSender } from '../ports.js';

/** Apple's servers for each kind of token. */
export const APNS_ORIGINS: Readonly<Record<PushEnvironment, string>> = {
  sandbox: 'https://api.sandbox.push.apple.com',
  production: 'https://api.push.apple.com',
};

export interface ApnsKey {
  /** The 10-character Key ID Apple shows for the `.p8` key. */
  readonly keyId: string;
  /** The Apple Developer Team ID. */
  readonly teamId: string;
  /** The `.p8` file's contents (a PEM EC private key). */
  readonly privateKey: string;
  /** The app's bundle id, which every notification is addressed to. */
  readonly topic: string;
}

/**
 * Apple wants a new provider token at most every 20 minutes and at least every 60: refreshed
 * after 50.
 */
const TOKEN_LIFETIME_MS = 50 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 10_000;

/**
 * Apple's reasons that mean the token will never work again: forget the device. Not
 * `DeviceTokenNotForTopic`: that one means our `APNS_TOPIC` is wrong, and fixing it should bring
 * every device back.
 */
const DEAD_TOKEN_REASONS = new Set(['BadDeviceToken', 'ExpiredToken', 'Unregistered']);

/** Answers Apple says to retry later: too many requests, or trouble on Apple's side. */
const RETRY_LATER_STATUSES = new Set([429, 500, 503]);

const ApnsError = z.object({ reason: z.string() });

/**
 * Sends straight to Apple Push Notification service over HTTP/2, signing in with a token-based
 * `.p8` key (no certificate to renew). One connection per APNs host, kept open, as Apple asks.
 * https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
 */
export function createApnsSender(
  key: ApnsKey,
  options: {
    readonly origins?: Readonly<Record<PushEnvironment, string>>;
    readonly now?: () => number;
  } = {},
): PushSender & { close(): void } {
  const origins = options.origins ?? APNS_ORIGINS;
  const now = options.now ?? Date.now;
  const privateKey = createPrivateKey(key.privateKey);
  const sessions = new Map<PushEnvironment, ClientHttp2Session>();
  let providerToken: { readonly jwt: string; readonly issuedAt: number } | undefined;

  function bearer(): string {
    const at = now();
    if (providerToken === undefined || at - providerToken.issuedAt >= TOKEN_LIFETIME_MS) {
      providerToken = { jwt: providerJwt(key, { privateKey, at }), issuedAt: at };
    }
    return providerToken.jwt;
  }

  function session(environment: PushEnvironment): ClientHttp2Session {
    const open = sessions.get(environment);
    if (open !== undefined && !open.closed && !open.destroyed) return open;
    const created = connect(origins[environment]);
    // A dropped connection is opened again on the next send.
    const forget = () => {
      if (sessions.get(environment) === created) sessions.delete(environment);
    };
    created.on('error', forget);
    created.on('close', forget);
    created.on('goaway', forget);
    created.unref();
    sessions.set(environment, created);
    return created;
  }

  return {
    async send(device, notification) {
      const body = JSON.stringify(apnsPayload(notification));
      const { status, text } = await post(session(device.environment), {
        headers: {
          [constants.HTTP2_HEADER_METHOD]: 'POST',
          [constants.HTTP2_HEADER_PATH]: `/3/device/${device.token}`,
          authorization: `bearer ${bearer()}`,
          'apns-topic': key.topic,
          'apns-push-type': 'alert',
          // 10 sends at once; 5 lets the phone save power, right for a quiet notification.
          'apns-priority': notification.interruption === 'passive' ? '5' : '10',
          ...(notification.collapseId === undefined
            ? {}
            : { 'apns-collapse-id': notification.collapseId }),
        },
        body,
      });
      if (status === 200) return 'sent';
      const reason = ApnsError.safeParse(safeJson(text)).data?.reason ?? 'Unknown';
      if (status === 410 || DEAD_TOKEN_REASONS.has(reason)) return 'gone';
      if (RETRY_LATER_STATUSES.has(status)) {
        throw new PushUnavailableError({
          cause: new Error(`APNs answered ${String(status)} ${reason}`),
        });
      }
      throw new PushRejectedError(status, reason);
    },

    close() {
      for (const open of sessions.values()) open.close();
      sessions.clear();
    },
  };
}

/** The ES256 JWT APNs takes as a provider token. */
function providerJwt(
  key: ApnsKey,
  { privateKey, at }: { readonly privateKey: KeyObject; readonly at: number },
): string {
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const unsigned = `${encode({ alg: 'ES256', kid: key.keyId })}.${encode({
    iss: key.teamId,
    iat: Math.floor(at / 1000),
  })}`;
  // JWS wants the raw r||s signature, not DER.
  const signature = sign('sha256', Buffer.from(unsigned), {
    key: privateKey,
    dsaEncoding: 'ieee-p1363',
  });
  return `${unsigned}.${signature.toString('base64url')}`;
}

function post(
  session: ClientHttp2Session,
  { headers, body }: { readonly headers: Record<string, string>; readonly body: string },
): Promise<{ status: number; text: string }> {
  return new Promise((resolve, reject) => {
    const stream = session.request(headers);
    stream.setTimeout(REQUEST_TIMEOUT_MS, () => {
      stream.close(constants.NGHTTP2_CANCEL);
      reject(new PushUnavailableError());
    });
    let status = 0;
    let text = '';
    stream.setEncoding('utf8');
    stream.on('response', (response) => {
      status = Number(response[constants.HTTP2_HEADER_STATUS]);
    });
    stream.on('data', (chunk: string) => {
      text += chunk;
    });
    stream.on('end', () => {
      resolve({ status, text });
    });
    stream.on('error', (error) => {
      reject(new PushUnavailableError({ cause: error }));
    });
    stream.end(body);
  });
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}
