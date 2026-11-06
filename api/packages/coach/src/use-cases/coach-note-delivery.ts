import type { CoachNoteDeliveryStore, MemberNote } from '../ports.js';

/** How far back a note may still be delivered: one written a day and a half ago is let go. */
const DELIVERY_WINDOW_MS = 36 * 60 * 60_000;

/** A morning note to deliver, with its coach's name now. */
export type NoteToDeliver = MemberNote & { readonly coachName: string };

/**
 * The morning notes to deliver: the server pushes each and tells it in the member's bell once
 * their clock reaches the morning hour, then marks it delivered.
 */
export interface CoachNoteDelivery {
  /** Notes written lately and not delivered yet, oldest first. */
  waiting(now: Date): Promise<readonly NoteToDeliver[]>;
  /** Marks a note delivered; says whether this call did, so two runs tell it once. */
  delivered(note: number): Promise<boolean>;
}

export function createCoachNoteDelivery(deps: {
  readonly store: CoachNoteDeliveryStore;
}): CoachNoteDelivery {
  return {
    waiting: (now) => deps.store.undelivered(new Date(now.getTime() - DELIVERY_WINDOW_MS)),
    delivered: (note) => deps.store.delivered(note),
  };
}
