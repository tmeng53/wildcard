import { z } from 'zod';

import type { MemberId } from './check-in.js';

/**
 * The replies a teammate can leave on a 今日请假条, apart from reactions (Tracy, 2026-10-20):
 * 准了 (`approved`), 抱抱 (`hug`) and 明天一起 (`together`), words still being settled, so the
 * list is this one enum. Like reactions, a member leaves at most one per 请假条 and can change
 * it. The app shows each with its own copy.
 */
export const ReplyKind = z.enum(['approved', 'hug', 'together']);
export type ReplyKind = z.infer<typeof ReplyKind>;

/** A member's reply to a 请假条. */
export interface Reply {
  readonly member: MemberId;
  readonly kind: ReplyKind;
  readonly repliedAt: Date;
}
