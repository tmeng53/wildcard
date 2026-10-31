import { z } from 'zod';

import { CheckInId, LocalDay, type CheckInRecord } from './check-in.js';

/** The kinds a member's history can be narrowed to. */
export const CheckInKind = z.enum(['trained', 'healthyMeal', 'cheatMeal', 'disclaimer']);
export type CheckInKind = z.infer<typeof CheckInKind>;

/** Most check-ins one page of a member's history holds, and how many it holds when not asked. */
export const MAX_PAGE = 60;
export const DEFAULT_PAGE = 30;

/**
 * Where a page of a member's history ends: the last check-in on it, in the history's order (newest
 * day first, then newest made, then by id). The next page starts after it, so check-ins saved
 * meanwhile never shift a page.
 */
export interface PostCursor {
  readonly day: LocalDay;
  readonly createdAt: Date;
  readonly id: CheckInId;
}

const Fields = z.strictObject({
  version: z.literal(1),
  day: LocalDay,
  createdAt: z.iso.datetime(),
  id: CheckInId,
});

/** The cursor as the app holds it: opaque, URL-safe text. */
export function encodeCursor({ day, createdAt, id }: PostCursor): string {
  return Buffer.from(
    JSON.stringify({ version: 1, day, createdAt: createdAt.toISOString(), id }),
  ).toString('base64url');
}

/** The cursor from its text, or undefined when it isn't one this server made. */
export function decodeCursor(text: string): PostCursor | undefined {
  let json: unknown;
  try {
    json = JSON.parse(Buffer.from(text, 'base64url').toString('utf8'));
  } catch {
    return undefined;
  }
  const parsed = Fields.safeParse(json);
  if (!parsed.success) return undefined;
  const { day, createdAt, id } = parsed.data;
  return { day, createdAt: new Date(createdAt), id };
}

/** The cursor just after this check-in. */
export function cursorAfter({ day, createdAt, id }: CheckInRecord): PostCursor {
  return { day, createdAt, id };
}
