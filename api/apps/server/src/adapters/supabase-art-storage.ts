import { ArtStorageUnavailableError, type ArtBlobs } from '@wildcard/art';
import { z } from 'zod';

// The public `art` bucket (supabase/migrations), on Supabase Storage's HTTP API with the
// project's secret key. Anyone may read it, through Storage's CDN; only the server writes, or an
// admin through a signed upload URL the server gives them. Each file is named by its SHA-256,
// so a name never changes what it holds and caches may keep it for a year.
// https://supabase.com/docs/guides/storage/cdn/fundamentals
// https://supabase.com/docs/reference/javascript/storage-from-upload
// https://supabase.com/docs/reference/javascript/storage-from-createsigneduploadurl

const BUCKET = 'art';
const SignedUpload = z.object({ url: z.string().startsWith('/object/upload/sign/') });
const StorageError = z.object({ statusCode: z.string().optional(), error: z.string().optional() });

/** The art bucket on Supabase Storage. */
export function createSupabaseArtStorage(options: {
  readonly supabaseUrl: string;
  readonly secretKey: string;
}): ArtBlobs {
  const base = `${options.supabaseUrl}/storage/v1`;
  const request = async (
    path: string,
    init: {
      readonly method?: 'POST';
      readonly headers?: Readonly<Record<string, string>>;
      readonly body?: Uint8Array;
    } = {},
  ): Promise<Response> => {
    try {
      return await fetch(`${base}${path}`, {
        method: init.method ?? 'GET',
        headers: {
          apikey: options.secretKey,
          authorization: `Bearer ${options.secretKey}`,
          ...init.headers,
        },
        ...(init.body === undefined ? {} : { body: init.body }),
        signal: AbortSignal.timeout(10_000),
      });
    } catch (cause) {
      throw new ArtStorageUnavailableError({ cause });
    }
  };
  const failed = async (response: Response) =>
    new ArtStorageUnavailableError({
      cause: new Error(`Storage answered ${String(response.status)}: ${await response.text()}`),
    });

  return {
    async put({ name, bytes, contentType }) {
      const response = await request(`/object/${BUCKET}/${name}`, {
        method: 'POST',
        headers: {
          'content-type': contentType,
          'cache-control': 'max-age=31536000',
          // Same name, same bytes: putting it again is harmless.
          'x-upsert': 'true',
        },
        body: bytes,
      });
      if (!response.ok) throw await failed(response);
    },

    async get(name) {
      const response = await request(`/object/${BUCKET}/${name}`);
      if (response.ok) return new Uint8Array(await response.arrayBuffer());
      const body: unknown = await response.json().catch(() => undefined);
      const { statusCode, error } = StorageError.safeParse(body).data ?? {};
      if (response.status === 404 || statusCode === '404' || error === 'not_found')
        return undefined;
      throw new ArtStorageUnavailableError({
        cause: new Error(`Storage answered ${String(response.status)}: ${JSON.stringify(body)}`),
      });
    },

    async uploadUrl(name) {
      const response = await request(`/object/upload/sign/${BUCKET}/${name}`, { method: 'POST' });
      if (!response.ok) throw await failed(response);
      return new URL(`${base}${SignedUpload.parse(await response.json()).url}`);
    },

    publicBase: new URL(`${base}/object/public/${BUCKET}/`),
  };
}
