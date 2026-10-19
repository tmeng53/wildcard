import { z } from '@hono/zod-openapi';
import { toProblemDetails } from '@wildcard/errors';

import { bodyVersion } from './body-version.js';
import { MediaTypeUnsupportedError } from './errors.js';

/**
 * Every failed request answers with this body, as `application/problem+json`: RFC 9457 problem
 * details plus `reason` (the exact failure, stable for clients to match on), `errorStatus` (its
 * general kind) and the `version` every body carries.
 * https://www.rfc-editor.org/rfc/rfc9457
 */
export const Problem = z
  .strictObject({
    version: bodyVersion(1),
    type: z.literal('about:blank'),
    title: z.string().meta({ description: 'The HTTP reason phrase.', example: 'Unauthorized' }),
    status: z.int().meta({ description: 'The HTTP status code.', example: 401 }),
    detail: z
      .string()
      .meta({ description: 'One sentence for people. Never shown as is in the app.' }),
    reason: z.string().meta({
      description: 'The exact failure. Never reworded once released; clients match on it.',
      example: 'AUTH_TOKEN_INVALID',
    }),
    errorStatus: z.string().meta({
      description: 'The general kind of failure, from a fixed list.',
      example: 'UNAUTHENTICATED',
    }),
  })
  .openapi('Problem');
export type Problem = z.infer<typeof Problem>;

/** The OpenAPI description of a failure response. */
export function problem(description: string) {
  return { description, content: { 'application/problem+json': { schema: Problem } } };
}

/** The failure every route with a JSON body documents: a body sent in another media type. */
export const jsonBodyFailures = {
  415: problem('The body isn’t sent as `application/json` (`MEDIA_TYPE_UNSUPPORTED`)'),
};

/** The response for a failed request. Anything that isn't one of our errors answers 500. */
export function problemResponse(error: unknown): Response {
  const body: Problem = { version: 1, ...toProblemDetails(error), ...httpOverride(error) };
  return new Response(JSON.stringify(body), {
    status: body.status,
    headers: { 'content-type': 'application/problem+json' },
  });
}

/** The HTTP status HTTP itself requires for an error, in place of its error status's usual one. */
function httpOverride(error: unknown) {
  // RFC 9110, 15.5.16: a body in a media type the route doesn't take is 415.
  if (error instanceof MediaTypeUnsupportedError) {
    return { status: 415, title: 'Unsupported Media Type' };
  }
  return {};
}
