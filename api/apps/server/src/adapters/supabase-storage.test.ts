import { randomUUID } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { PhotoPath } from '../ports.js';
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

  it('signs view URLs that expire', async () => {
    const path = newPath();
    await fetch(await photos.createUploadUrl(path), {
      method: 'PUT',
      headers: { 'content-type': 'image/webp' },
      body: 'RIFF',
    });
    const url = await photos.createViewUrl(path, 1);
    expect(await (await fetch(url)).text()).toBe('RIFF');
    await new Promise((resolve) => setTimeout(resolve, 2_100));
    const expired = await fetch(url);
    expect(expired.ok).toBe(false);
    expect(await expired.json()).toMatchObject({ code: 'InvalidJWT' });
  });

  it('refuses to sign a view URL for a photo that was never uploaded', async () => {
    expect(await reasonOf(photos.createViewUrl(newPath(), 60))).toBe('PHOTO_NOT_FOUND');
  });

  it('refuses a wrong secret key as unavailable, not as a missing photo', async () => {
    const wrong = createSupabasePhotoStorage({
      supabaseUrl: config.supabaseUrl,
      secretKey: 'sb_secret_not-the-key',
    });
    expect(await reasonOf(wrong.exists(newPath()))).toBe('PHOTO_STORAGE_UNAVAILABLE');
    expect(await reasonOf(wrong.createUploadUrl(newPath()))).toBe('PHOTO_STORAGE_UNAVAILABLE');
  });
});
