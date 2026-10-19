import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresWeeklyPlanStore,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import { PhotoPath } from '../ports.js';
import { config, signUp } from '../test-kit/local-supabase.js';

// The whole journey against local Supabase: sign in, ask for an upload URL, upload to it.
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';

async function createPhotoUpload(headers: Record<string, string>, storageUrl = config.supabaseUrl) {
  const db = createDatabase(config.databaseUrl);
  const photos = createSupabasePhotoStorage({
    supabaseUrl: storageUrl,
    secretKey: config.supabaseSecretKey,
  });
  const app = createApp({
    db,
    verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
    photos,
    checkIns: createCheckIns({
      store: createPostgresCheckInStore(db),
      photos,
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    weeklyPlans: createWeeklyPlans({
      store: createPostgresWeeklyPlanStore(db),
      calendarOf: () => Promise.resolve(undefined),
      clock: () => new Date(),
    }),
    members: createMembers({ store: createPostgresProfileStore(db) }),
    log: createLog(() => undefined),
  });
  try {
    const response = await app.request('/photo-uploads', { method: 'POST', headers });
    return {
      status: response.status,
      type: response.headers.get('content-type'),
      body: z.record(z.string(), z.unknown()).parse(await response.json()),
    };
  } finally {
    await db.destroy();
  }
}

/**
 * Uploads a file to a signed URL the way the app does. Storage answers every refusal with HTTP
 * 400 and the reason in the body, so this answers the body's code.
 */
async function upload(url: unknown, file: { body: Uint8Array | string; contentType?: string }) {
  const response = await fetch(String(url), {
    method: 'PUT',
    headers: { 'content-type': file.contentType ?? 'image/jpeg' },
    body: file.body,
  });
  if (response.ok) return 'uploaded';
  return z.object({ code: z.string() }).parse(await response.json()).code;
}

describe('POST /photo-uploads', () => {
  it('gives a signed-in member a URL in their own folder that takes one photo', async () => {
    const { token, userId } = await signUp();
    const { status, type, body } = await createPhotoUpload({ authorization: `Bearer ${token}` });
    expect([status, type]).toStrictEqual([201, 'application/json']);
    expect(Object.keys(body).sort()).toStrictEqual(['path', 'uploadUrl', 'version']);
    expect(body.version).toBe(1);
    expect(body.path).toMatch(new RegExp(`^${userId}/${UUID}$`));
    expect(body.uploadUrl).toMatch(
      new RegExp(
        `^${config.supabaseUrl}/storage/v1/object/upload/sign/check-in-photos/${String(body.path)}\\?token=`,
      ),
    );

    expect(await upload(body.uploadUrl, { body: JPEG })).toBe('uploaded');
    const photos = createSupabasePhotoStorage({
      supabaseUrl: config.supabaseUrl,
      secretKey: config.supabaseSecretKey,
    });
    const path = PhotoPath.parse(body.path);
    expect(await photos.exists(path)).toBe(true);
    const view = await fetch(
      z.instanceof(URL).parse((await photos.createViewUrls([path], 60)).get(path)),
    );
    expect(new Uint8Array(await view.arrayBuffer())).toStrictEqual(JPEG);

    // The same URL can never replace the photo, even before a check-in uses it.
    expect(await upload(body.uploadUrl, { body: 'something else' })).toBe('KeyAlreadyExists');
    const again = await fetch(
      z.instanceof(URL).parse((await photos.createViewUrls([path], 60)).get(path)),
    );
    expect(new Uint8Array(await again.arrayBuffer())).toStrictEqual(JPEG);
  });

  it('gives every request a new path', async () => {
    const { token } = await signUp();
    const headers = { authorization: `Bearer ${token}` };
    const first = await createPhotoUpload(headers);
    const second = await createPhotoUpload(headers);
    expect(first.body.path).not.toBe(second.body.path);
  });

  it.each([
    {
      name: 'a file that isn’t a photo',
      code: 'InvalidMimeType',
      body: 'hi',
      contentType: 'text/plain',
    },
    {
      name: 'a photo over 10 MiB',
      code: 'EntityTooLarge',
      body: new Uint8Array(10 * 1024 * 1024 + 1),
    },
  ])('refuses $name', async ({ code, ...file }) => {
    const { token } = await signUp();
    const { body } = await createPhotoUpload({ authorization: `Bearer ${token}` });
    expect(await upload(body.uploadUrl, file)).toBe(code);
    const photos = createSupabasePhotoStorage({
      supabaseUrl: config.supabaseUrl,
      secretKey: config.supabaseSecretKey,
    });
    expect(await photos.exists(PhotoPath.parse(body.path))).toBe(false);
  });

  it('asks a caller with no token to sign in', async () => {
    const { status, body } = await createPhotoUpload({});
    expect([status, body.reason]).toStrictEqual([401, 'AUTH_TOKEN_MISSING']);
  });

  it('answers 503 when photo storage can’t be reached', async () => {
    const { token } = await signUp();
    // Nothing listens on port 1.
    expect(
      await createPhotoUpload({ authorization: `Bearer ${token}` }, 'http://127.0.0.1:1'),
    ).toStrictEqual({
      status: 503,
      type: 'application/problem+json',
      body: {
        version: 1,
        type: 'about:blank',
        title: 'Service Unavailable',
        status: 503,
        detail: 'Photos are unavailable right now. Try again shortly.',
        reason: 'PHOTO_STORAGE_UNAVAILABLE',
        errorStatus: 'UNAVAILABLE',
      },
    });
  });
});
