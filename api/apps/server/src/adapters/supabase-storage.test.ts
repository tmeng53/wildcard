import { randomUUID } from 'node:crypto';

import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { PhotoPath, UserId } from '../ports.js';
import { config } from '../test-kit/local-supabase.js';
import { createSupabasePhotoStorage } from './supabase-storage.js';

// Against local Supabase Storage and the bucket the migration creates.
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const newPath = () => PhotoPath.parse(`${randomUUID()}/${randomUUID()}`);

async function reasonOf(promise: Promise<unknown>) {
  try {
    return await promise;
  } catch (error) {
    return error instanceof Error && 'reason' in error ? error.reason : error;
  }
}

describe('createSupabasePhotoStorage', () => {
  it('says a photo exists only once it is uploaded', async () => {
    const path = newPath();
    const url = await photos.createUploadUrl(path);
    expect(await photos.exists(path)).toBe(false);
    const put = await fetch(url, {
      method: 'PUT',
      headers: { 'content-type': 'image/png' },
      body: new Uint8Array([0x89, 0x50, 0x4e, 0x47]),
    });
    expect(put.status).toBe(200);
    expect(await photos.exists(path)).toBe(true);
  });

  it('signs view URLs for several photos at once, which expire', async () => {
    const [first, second] = [newPath(), newPath()];
    for (const [path, body] of [
      [first, 'RIFF'],
      [second, 'RIFF2'],
    ] as const) {
      await fetch(await photos.createUploadUrl(path), {
        method: 'PUT',
        headers: { 'content-type': 'image/webp' },
        body,
      });
    }
    const urls = await photos.createViewUrls([second, first], 1);
    expect([...urls.keys()]).toStrictEqual([second, first]);
    const url = z.instanceof(URL).parse(urls.get(first));
    expect(await (await fetch(url)).text()).toBe('RIFF');
    expect(await (await fetch(z.instanceof(URL).parse(urls.get(second)))).text()).toBe('RIFF2');
    await new Promise((resolve) => setTimeout(resolve, 2_100));
    const expired = await fetch(url);
    expect(expired.ok).toBe(false);
    expect(await expired.json()).toMatchObject({ code: 'InvalidJWT' });
  });

  it('refuses to sign view URLs when a photo was never uploaded', async () => {
    const path = newPath();
    await fetch(await photos.createUploadUrl(path), { method: 'PUT', body: 'RIFF' });
    expect(await reasonOf(photos.createViewUrls([path, newPath()], 60))).toBe('PHOTO_NOT_FOUND');
  });

  it('signs nothing for no photos, without calling Storage', async () => {
    const offline = createSupabasePhotoStorage({
      supabaseUrl: 'http://127.0.0.1:9',
      secretKey: 'sb_secret_unused',
    });
    expect((await offline.createViewUrls([], 60)).size).toBe(0);
  });

  it('refuses a wrong secret key as unavailable, not as a missing photo', async () => {
    const wrong = createSupabasePhotoStorage({
      supabaseUrl: config.supabaseUrl,
      secretKey: 'sb_secret_not-the-key',
    });
    expect(await reasonOf(wrong.exists(newPath()))).toBe('PHOTO_STORAGE_UNAVAILABLE');
    expect(await reasonOf(wrong.createUploadUrl(newPath()))).toBe('PHOTO_STORAGE_UNAVAILABLE');
  });

  it('deletes every photo in one member’s folder and no one else’s, and a repeat is fine', async () => {
    const member = randomUUID();
    const other = randomUUID();
    const upload = async (folder: string) => {
      const path = PhotoPath.parse(`${folder}/${randomUUID()}`);
      await fetch(await photos.createUploadUrl(path), {
        method: 'PUT',
        headers: { 'content-type': 'image/webp' },
        body: 'RIFF',
      });
      return path;
    };
    const mine = [await upload(member), await upload(member), await upload(member)];
    const theirs = await upload(other);
    const exist = () => Promise.all([...mine, theirs].map((path) => photos.exists(path)));
    expect(await exist()).toStrictEqual([true, true, true, true]);
    await photos.deleteAllOf(UserId.parse(member));
    expect(await exist()).toStrictEqual([false, false, false, true]);
    await photos.deleteAllOf(UserId.parse(member));
    await photos.deleteAllOf(UserId.parse(randomUUID()));
  });

  it('says Storage is unavailable when deleting with a wrong secret key', async () => {
    const wrong = createSupabasePhotoStorage({
      supabaseUrl: config.supabaseUrl,
      secretKey: 'sb_secret_not-the-key',
    });
    expect(await reasonOf(wrong.deleteAllOf(UserId.parse(randomUUID())))).toBe(
      'PHOTO_STORAGE_UNAVAILABLE',
    );
  });
});
