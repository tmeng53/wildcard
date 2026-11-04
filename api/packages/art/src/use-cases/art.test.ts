import { createHash, randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresArtStore, type ArtTables } from '../adapters/postgres-art-store.js';
import { ArtPath } from '../domain/art.js';
import { ArtFileMissingError, ArtRefusedError } from '../errors.js';
import type { ArtBlobs } from '../ports.js';
import { createArt } from './art.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<ArtTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

/** The bucket, kept in memory: the Storage adapter has its own test against local Supabase. */
function memoryBlobs() {
  const kept = new Map<string, Uint8Array>();
  const blobs: ArtBlobs = {
    put: ({ name, bytes }) => {
      kept.set(name, bytes);
      return Promise.resolve();
    },
    get: (name) => Promise.resolve(kept.get(name)),
    uploadUrl: (name) => Promise.resolve(new URL(`https://storage.test/upload/${name}`)),
    publicBase: new URL('https://storage.test/art/'),
  };
  return { blobs, kept };
}

// Each test works under its own folder, so tests share the table without seeing each other.
const folder = () => `avatar/art/top/t${randomUUID().slice(0, 8)}`;
const svg =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 320"><circle cx="1" cy="1" r="1" fill="#FFFFFF"/></svg>';
const sha = (text: string | Uint8Array) => createHash('sha256').update(text).digest('hex');
const admin = randomUUID();
const ours = (files: readonly { path: string }[], under: string) =>
  files.filter(({ path }) => path.startsWith(under));

describe('art', () => {
  it('puts files under their SHA-256, as one generation', async () => {
    const { blobs, kept } = memoryBlobs();
    const art = createArt({ store: createPostgresArtStore(db), blobs });
    const under = folder();
    const before = await art.manifest();

    const after = await art.put(
      {
        files: [
          { path: ArtPath.parse(`${under}/torso.svg`), text: svg },
          { path: ArtPath.parse(`${under}/tones.json`), text: '{"version":1,"base":"#2D5BA0"}' },
        ],
        rigVersion: 1,
      },
      admin,
    );

    expect(after.generation).toBeGreaterThan(before.generation);
    expect(ours(after.files, under)).toEqual([
      {
        path: `${under}/tones.json`,
        sha256: sha('{"version":1,"base":"#2D5BA0"}'),
        size: 30,
        rigVersion: 1,
      },
      { path: `${under}/torso.svg`, sha256: sha(svg), size: svg.length, rigVersion: 1 },
    ]);
    expect([...kept.keys()]).toContain(`${sha(svg)}.svg`);
    expect((await art.manifest()).baseUrl.href).toBe('https://storage.test/art/');
  });

  it('takes an uploaded file by its SHA-256, checking it is that file', async () => {
    const { blobs } = memoryBlobs();
    const art = createArt({ store: createPostgresArtStore(db), blobs });
    const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
    const path = ArtPath.parse(`scenes/s${randomUUID().slice(0, 8)}-day@3x.png`);

    await expect(
      art.put({ files: [{ path, sha256: sha(png) }], rigVersion: 1 }, admin),
    ).rejects.toThrow(ArtFileMissingError);
    await blobs.put({ name: `${sha(png)}.png`, bytes: png, contentType: 'image/png' });
    const after = await art.put({ files: [{ path, sha256: sha(png) }], rigVersion: 2 }, admin);
    expect(after.files.find((file) => file.path === path)).toEqual({
      path,
      sha256: sha(png),
      size: 11,
      rigVersion: 2,
    });

    await blobs.put({ name: `${'0'.repeat(64)}.png`, bytes: png, contentType: 'image/png' });
    await expect(
      art.put({ files: [{ path, sha256: '0'.repeat(64) }], rigVersion: 1 }, admin),
    ).rejects.toThrow('the uploaded file’s SHA-256 isn’t the one given');
  });

  it('changes nothing when one file is refused', async () => {
    const { blobs } = memoryBlobs();
    const art = createArt({ store: createPostgresArtStore(db), blobs });
    const under = folder();
    const before = await art.manifest();

    await expect(
      art.put(
        {
          files: [
            { path: ArtPath.parse(`${under}/torso.svg`), text: svg },
            {
              path: ArtPath.parse(`${under}/armL.svg`),
              text: '<svg viewBox="0 0 1 1"><text>hi</text></svg>',
            },
          ],
          rigVersion: 1,
        },
        admin,
      ),
    ).rejects.toThrow(ArtRefusedError);
    expect((await art.manifest()).generation).toBe(before.generation);
  });

  it('takes paths back to the bundled files, once', async () => {
    const { blobs } = memoryBlobs();
    const art = createArt({ store: createPostgresArtStore(db), blobs });
    const under = folder();
    const path = ArtPath.parse(`${under}/torso.svg`);
    await art.put({ files: [{ path, text: svg }], rigVersion: 1 }, admin);

    const retired = await art.retire({ paths: [path] }, admin);
    expect(ours(retired.files, under)).toEqual([]);
    const again = await art.retire({ paths: [path] }, admin);
    expect(again.generation).toBe(retired.generation);
  });
});
