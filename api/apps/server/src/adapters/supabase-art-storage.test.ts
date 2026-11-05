import { createHash, randomUUID } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { config } from '../test-kit/local-supabase.js';
import { createSupabaseArtStorage } from './supabase-art-storage.js';

// Against local Supabase Storage and the public bucket the migration creates.
const art = createSupabaseArtStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const nameOf = (bytes: string, extension: string) =>
  `${createHash('sha256').update(bytes).digest('hex')}.${extension}`;

describe('createSupabaseArtStorage', () => {
  it('keeps a file anyone can download, and puts it again harmlessly', async () => {
    const json = `{"version":1,"id":"${randomUUID()}"}`;
    const name = nameOf(json, 'json');
    expect(await art.get(name)).toBeUndefined();
    await art.put({ name, bytes: new TextEncoder().encode(json), contentType: 'application/json' });
    await art.put({ name, bytes: new TextEncoder().encode(json), contentType: 'application/json' });

    expect(new TextDecoder().decode(await art.get(name))).toBe(json);
    const downloaded = await fetch(new URL(name, art.publicBase));
    expect(downloaded.status).toBe(200);
    expect(await downloaded.text()).toBe(json);
  });

  it('signs an upload URL an admin puts a file to', async () => {
    const png = `\x89PNG${randomUUID()}`;
    const name = nameOf(png, 'png');
    const put = await fetch(await art.uploadUrl(name), {
      method: 'PUT',
      headers: { 'content-type': 'image/png' },
      body: png,
    });
    expect(put.status).toBe(200);
    expect(new TextDecoder().decode(await art.get(name))).toBe(png);
  });
});
