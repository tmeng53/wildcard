import { z } from '@hono/zod-openapi';

/**
 * The top-level `version` every request and response body carries, so a reader can always tell
 * which shape it holds. Typed `integer` in OpenAPI (Zod alone says `number`), so the generated
 * Swift is an `Int` enum. Until Wildcard has real users, shapes change in place at version 1.
 */
export function bodyVersion<const V extends number>(version: V) {
  return z.literal(version).openapi({ type: 'integer', enum: [version] });
}
