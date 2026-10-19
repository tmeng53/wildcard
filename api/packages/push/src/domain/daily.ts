import { z } from 'zod';

import type { MemberId } from './device.js';

/** A day on a member's own calendar, `YYYY-MM-DD`, in their time zone. */
export const LocalDay = z.iso.date().brand<'LocalDay'>();
export type LocalDay = z.infer<typeof LocalDay>;

/** A member whose daily push may be due, on their own today. */
export interface DailyCandidate {
  readonly member: MemberId;
  readonly day: LocalDay;
}
