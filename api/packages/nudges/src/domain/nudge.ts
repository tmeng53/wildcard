import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

export const SquadId = z.uuid().brand<'SquadId'>();
export type SquadId = z.infer<typeof SquadId>;

/**
 * What a nudge asks: 催你练 (`train`) or 好好休息 (`rest`). The kind is also the name the app's
 * String Catalog keys its copy by, so each reads as its own thing: only `train` is a push to
 * work out; `rest` is care.
 */
export const NudgeKind = z.enum(['train', 'rest']);
export type NudgeKind = z.infer<typeof NudgeKind>;

/** A local day, `YYYY-MM-DD`. */
export type LocalDay = string;

/** One nudge from a squadmate: at most one of each kind from one member to another a day. */
export interface Nudge {
  readonly from: MemberId;
  readonly to: MemberId;
  /** The squad they share, which it was sent in. */
  readonly squad: SquadId;
  readonly kind: NudgeKind;
  /** The day on the sender's clock. */
  readonly day: LocalDay;
  readonly at: Date;
}

/** The day `at` falls on in `timeZone` (an IANA zone). */
export function localDay(at: Date, timeZone: string): LocalDay {
  // en-CA writes dates as YYYY-MM-DD.
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(at);
}
