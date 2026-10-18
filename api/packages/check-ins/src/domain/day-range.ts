import { z } from 'zod';

import { LocalDay } from './check-in.js';

/** The most days one list returns: a month on the track. */
const MAX_DAYS = 31;
const DAY = 86_400_000;

/** Days `from` to `to`, both included, at most 31 of them. */
export const DayRange = z
  .strictObject({ from: LocalDay, to: LocalDay })
  .refine(({ from, to }) => from <= to, { message: '`from` must not be after `to`', path: ['to'] })
  .refine(({ from, to }) => (Date.parse(to) - Date.parse(from)) / DAY < MAX_DAYS, {
    message: `At most ${String(MAX_DAYS)} days at a time`,
    path: ['to'],
  });
export type DayRange = z.infer<typeof DayRange>;
