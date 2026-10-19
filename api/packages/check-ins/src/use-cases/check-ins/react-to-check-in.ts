import type { CheckInId, CheckInRecord, MemberId } from '../../domain/check-in.js';
import type { Reaction, ReactionKind, ReactOutcome } from '../../domain/reaction.js';
import { OwnCheckInReactionError } from '../../errors.js';
import type { CheckInStore, Clock, ReactionStore } from '../../ports.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';

export interface ReactToCheckInInput {
  readonly checkIn: CheckInId;
  readonly member: MemberId;
  readonly kind: ReactionKind;
}

export interface Reacted {
  readonly checkIn: CheckInRecord;
  readonly reaction: Reaction;
  readonly outcome: ReactOutcome;
}

/**
 * Leaves the member's reaction on a teammate's check-in, in place of any they left before. The
 * same reaction again changes nothing (not even its time), so a retry is safe. Throws
 * `CheckInNotFoundError` for a check-in they can't see and `OwnCheckInReactionError` for their own.
 */
export async function reactToCheckIn(
  {
    store,
    reactions,
    clock,
  }: { readonly store: CheckInStore; readonly reactions: ReactionStore; readonly clock: Clock },
  { checkIn: id, member, kind }: ReactToCheckInInput,
): Promise<Reacted> {
  const checkIn = await findVisibleCheckIn(store, { id, viewer: member });
  if (checkIn.member === member) throw new OwnCheckInReactionError();
  const asked = { member, kind, reactedAt: clock() };
  const outcome = await reactions.save(id, asked);
  // Unchanged keeps the time it was first left.
  const saved = (await reactions.list(id)).find((reaction) => reaction.member === member);
  // Taken off by a removal that ran at the same moment: answer with what was asked.
  return { checkIn, reaction: saved ?? asked, outcome };
}
