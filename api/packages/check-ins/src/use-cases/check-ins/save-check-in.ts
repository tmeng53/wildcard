import { checkCheckInTime } from '../../domain/check-in-time.js';
import {
  isSameCheckIn,
  recordFromDraft,
  type CheckInDraft,
  type CheckInId,
  type CheckInRecord,
  type MemberId,
} from '../../domain/check-in.js';
import {
  CheckInIdConflictError,
  DisclaimerAlreadyPostedError,
  SquadNotJoinedError,
} from '../../errors.js';
import type { CheckInStore, Clock } from '../../ports.js';

export interface SaveCheckInInput {
  readonly id: CheckInId;
  readonly member: MemberId;
  readonly draft: CheckInDraft;
}

export interface SavedCheckIn {
  readonly checkIn: CheckInRecord;
  /** False when this save was a retry of one already saved. */
  readonly created: boolean;
}

/**
 * Saves a member's check-in under the id the app made, so a retry is safe: the same check-in
 * again is a success, different contents under a saved id are refused. A retry is recognised
 * before the time checks, so a late retry of a saved check-in still succeeds.
 */
export async function saveCheckIn(
  { store, clock }: { readonly store: CheckInStore; readonly clock: Clock },
  { id, member, draft }: SaveCheckInInput,
): Promise<SavedCheckIn> {
  const checkIn = recordFromDraft(draft, { id, member });
  const retry = await asRetry(store, checkIn);
  if (retry !== undefined) return retry;

  checkCheckInTime(checkIn, clock());
  const joined = await store.squadsOf(member);
  const notJoined = checkIn.audience.find((squad) => !joined.has(squad));
  if (notJoined !== undefined) throw new SquadNotJoinedError(notJoined);

  const outcome = await store.insert(checkIn);
  if (outcome.saved) return { checkIn, created: true };
  // A save of the same id may have finished while this one ran.
  const overlapping = await asRetry(store, checkIn);
  if (overlapping !== undefined) return overlapping;
  if (outcome.taken === 'dailyDisclaimer') throw new DisclaimerAlreadyPostedError(checkIn.day);
  throw new CheckInIdConflictError(id);
}

/** The saved check-in when `checkIn` repeats it; undefined when its id is free. */
async function asRetry(
  store: CheckInStore,
  checkIn: CheckInRecord,
): Promise<SavedCheckIn | undefined> {
  const saved = await store.find(checkIn.id);
  if (saved === undefined) return undefined;
  if (!isSameCheckIn(saved, checkIn)) throw new CheckInIdConflictError(checkIn.id);
  return { checkIn: saved, created: false };
}
