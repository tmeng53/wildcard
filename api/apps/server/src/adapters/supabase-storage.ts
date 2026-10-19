import { z } from 'zod';

import { PhotoNotFoundError, PhotoStorageUnavailableError } from '../errors.js';
import type { PhotoPath, PhotoStorage } from '../ports.js';

// Supabase Storage's HTTP API, called with the project's secret key, which only the server
// holds. The bucket is private with no policies (supabase/migrations), so the app's own tokens
// can't reach it; it gets signed URLs from us. Upload URLs last 2 hours, a Supabase default.
// https://supabase.com/docs/reference/javascript/storage-from-createsigneduploadurl
// https://supabase.com/docs/reference/javascript/storage-from-createsignedurls
// https://supabase.com/docs/reference/javascript/storage-from-list
// https://supabase.com/docs/reference/javascript/storage-from-remove

/** The check-in photos bucket, created by the migration with its size and type limits. */
const BUCKET = 'check-in-photos';

// Plain `z.object`: a third party's payloads, which carry more fields than we read.
const SignedUpload = z.object({ url: z.string().startsWith('/object/upload/sign/') });
// One entry per path asked for; a missing photo has an `error` and no URL.
const SignedViews = z.array(
  z.object({ path: z.string(), signedURL: z.string().startsWith('/object/sign/').nullable() }),
);
const StorageError = z.object({ code: z.string() });
// The files in one folder, by name within it.
const Listed = z.array(z.object({ name: z.string() }));

/** The most Storage lists at once; a fuller folder is deleted a page at a time. */
const LIST_LIMIT = 1000;

/** The photo storage port on Supabase Storage. */
export function createSupabasePhotoStorage(options: {
  readonly supabaseUrl: string;
  readonly secretKey: string;
}): PhotoStorage {
  const base = `${options.supabaseUrl}/storage/v1`;

  /** Calls Storage; answers its JSON body, or `undefined` when it says the object is missing. */
  const call = async (request: {
    readonly method: 'GET' | 'POST' | 'DELETE';
    readonly path: string;
    readonly body?: unknown;
  }): Promise<unknown> => {
    const { method, path, body } = request;
    let response: Response;
    try {
      response = await fetch(`${base}${path}`, {
        method,
        headers: {
          apikey: options.secretKey,
          // Storage would let a second upload replace the first; a photo is never replaced.
          'x-upsert': 'false',
          ...(body === undefined ? {} : { 'content-type': 'application/json' }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(5_000),
      });
    } catch (cause) {
      throw new PhotoStorageUnavailableError({ cause });
    }
    const json: unknown = await response.json().catch(() => undefined);
    if (response.ok) return json;
    // Storage answers a missing object with HTTP 400 and `NoSuchKey` in the body.
    if (StorageError.safeParse(json).data?.code === 'NoSuchKey') return undefined;
    throw new PhotoStorageUnavailableError({
      cause: new Error(`Storage answered ${String(response.status)}: ${JSON.stringify(json)}`),
    });
  };

  /** Calls Storage for a JSON answer, failing when it says something is missing. */
  const callFor = async (request: Parameters<typeof call>[0]): Promise<unknown> => {
    const json = await call(request);
    if (json === undefined) {
      throw new PhotoStorageUnavailableError({ cause: new Error(`${request.path}: NoSuchKey`) });
    }
    return json;
  };

  /** Storage's relative URLs are under /storage/v1. */
  const absolute = (relative: string) => new URL(`${base}${relative}`);
  const object = (path: PhotoPath) => `${BUCKET}/${path}`;

  return {
    async createUploadUrl(path) {
      const json = await call({ method: 'POST', path: `/object/upload/sign/${object(path)}` });
      return absolute(SignedUpload.parse(json).url);
    },
    async exists(path) {
      return (await call({ method: 'GET', path: `/object/info/${object(path)}` })) !== undefined;
    },
    async createViewUrls(paths, expiresInSeconds) {
      // Storage refuses an empty list.
      if (paths.length === 0) return new Map();
      const json = await call({
        method: 'POST',
        path: `/object/sign/${BUCKET}`,
        body: { expiresIn: expiresInSeconds, paths },
      });
      const signed = new Map(
        SignedViews.parse(json).map(({ path, signedURL }) => [path, signedURL] as const),
      );
      return new Map(
        paths.map((path) => {
          const url = signed.get(path);
          if (url === undefined || url === null) throw new PhotoNotFoundError(path);
          return [path, absolute(url)] as const;
        }),
      );
    },
    async deleteAllOf(member) {
      // Each round deletes what the folder lists until it lists nothing, so a repeat, or a
      // photo uploaded meanwhile, is covered too.
      for (;;) {
        const listed = Listed.parse(
          await callFor({
            method: 'POST',
            path: `/object/list/${BUCKET}`,
            body: { prefix: `${member}/`, limit: LIST_LIMIT },
          }),
        );
        if (listed.length === 0) return;
        const deleted = Listed.parse(
          await callFor({
            method: 'DELETE',
            path: `/object/${BUCKET}`,
            body: { prefixes: listed.map(({ name }) => `${member}/${name}`) },
          }),
        );
        // Never loop on a listing that deleting doesn't shrink.
        if (deleted.length === 0) {
          throw new PhotoStorageUnavailableError({
            cause: new Error(`Storage deleted none of ${String(listed.length)} listed photos`),
          });
        }
      }
    },
  };
}
