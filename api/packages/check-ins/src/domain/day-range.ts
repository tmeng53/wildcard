import { z } from 'zod';

import { LocalDay } from './check-in.js';

/** The most days one list returns: a month on the track. */
const MAX_DAYS = 31;
const DAY = 86_400_000;

interface Days {
  readonly from: string;
  readonly to: string;
}
const inOrder = ({ from, to }: Days) => from <= to;
const inOrderIssue = { message: '`from` must not be after `to`', path: ['to'] };
const withinMonth = ({ from, to }: Days) => (Date.parse(to) - Date.parse(from)) / DAY < MAX_DAYS;
const withinMonthIssue = { message: `At most ${String(MAX_DAYS)} days at a time`, path: ['to'] };

/** Days `from` to `to`, both included, at most 31 of them. */
export const DayRange = z
  .strictObject({ from: LocalDay, to: LocalDay })
  .refine(inOrder, inOrderIssue)
  .refine(withinMonth, withinMonthIssue);
export type DayRange = z.infer<typeof DayRange>;

/**
 * Whether a member's own list keeps their posts shared to no squad. Builds from before sharing
 * was optional can't read one, so it is left out unless asked for.
 */
export const Unshared = z.enum(['include']).meta({
  description:
    '`include` lists posts shared to no squad too; left out, they are not listed, since ' +
    'builds from before they existed can’t read them.',
});
export type Unshared = z.infer<typeof Unshared>;

/** A `DayRange` for the member's own list, which may ask for their unshared posts. */
export const MyDayRange = z
  .strictObject({ from: LocalDay, to: LocalDay, unshared: Unshared.optional() })
  .refine(inOrder, inOrderIssue)
  .refine(withinMonth, withinMonthIssue);
export type MyDayRange = z.infer<typeof MyDayRange>;
