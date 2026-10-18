import { z } from 'zod';

import { PhotoNotFoundError, PhotoStorageUnavailableError } from '../errors.js';
import type { PhotoPath, PhotoStorage } from '../ports.js';

// Supabase Storage's HTTP API, called with the project's secret key, which only the server
// holds. The bucket is private with no policies (supabase/migrations), so the app's own tokens
// can't reach it; it gets signed URLs from us. Upload URLs last 2 hours, a Supabase default.
// https://supabase.com/docs/reference/javascript/storage-from-createsigneduploadurl

/** The check-in photos bucket, created by the migration with its size and type limits. */
const BUCKET = 'check-in-photos';

// Plain `z.object`: a third party's payloads, which carry more fields than we read.
const SignedUpload = z.object({ url: z.string().startsWith('/object/upload/sign/') });
const SignedView = z.object({ signedURL: z.string().startsWith('/object/sign/') });
const StorageError = z.object({ code: z.string() });

/** The photo storage port on Supabase Storage. */
export function createSupabasePhotoStorage(options: {
  readonly supabaseUrl: string;
  readonly secretKey: string;
}): PhotoStorage {
  const base = `${options.supabaseUrl}/storage/v1`;

  /** Calls Storage; answers its JSON body, or `undefined` when it says the object is missing. */
  const call = async (request: {
    readonly method: 'GET' | 'POST';
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
    async createViewUrl(path, expiresInSeconds) {
      const json = await call({
        method: 'POST',
        path: `/object/sign/${object(path)}`,
        body: { expiresIn: expiresInSeconds },
      });
      if (json === undefined) throw new PhotoNotFoundError(path);
      return absolute(SignedView.parse(json).signedURL);
    },
  };
}
