import { randomUUID } from 'node:crypto';

import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';

import { bodyVersion } from '../body-version.js';
import { PhotoPath, type PhotoStorage, type VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

export const PhotoUpload = z
  .strictObject({
    version: bodyVersion(1),
    path: z.string().meta({
      description:
        'The photo’s name, `<member id>/<photo id>`. A check-in lists it in `photos` once the ' +
        'upload is done.',
      example: '3f0c8a52-6f39-4c39-9a51-0c7c3c4a4f1e/9b2e1d4c-7a8f-4e2b-8c1d-2f3a4b5c6d7e',
    }),
    uploadUrl: z.url().meta({
      description:
        'Upload the photo here with `PUT`, the file as the body and its `Content-Type` (JPEG, ' +
        'HEIC, PNG or WebP, at most 10 MiB). It works for 2 hours and only once.',
    }),
  })
  .openapi('PhotoUpload');

/**
 * `POST /photo-uploads`: a place to upload one check-in photo, in the caller's own folder. The
 * app asks once per photo (a check-in has up to 3), uploads, then saves the check-in with the
 * paths.
 */
export function photoUploads(deps: {
  readonly verifyToken: VerifyToken;
  readonly photos: PhotoStorage;
}) {
  const route = createRoute({
    method: 'post',
    path: '/photo-uploads',
    operationId: 'createPhotoUpload',
    summary: 'A signed URL to upload one check-in photo to',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      201: {
        description: 'Ready to upload',
        content: { 'application/json': { schema: PhotoUpload } },
      },
      401: problem('No bearer token, or not a valid one'),
      503: problem('Sign-in or photo storage can’t be reached right now'),
    },
  });
  return new OpenAPIHono<SignedIn>().openapi(route, async (c) => {
    const path = PhotoPath.parse(`${c.var.caller.userId}/${randomUUID()}`);
    const uploadUrl = await deps.photos.createUploadUrl(path);
    return c.json({ version: 1, path, uploadUrl: uploadUrl.href } as const, 201);
  });
}
