import { CUSTOM_SPORT } from '@wildcard/sport-ids';

import { checkCheckInTime } from '../../domain/check-in-time.js';
import {
  isSameCheckIn,
  photosOf,
  recordFromDraft,
  type CheckInDraft,
  type CheckInId,
  type CheckInRecord,
  type MemberId,
} from '../../domain/check-in.js';
import { isOwnPhoto } from '../../domain/photos.js';
import {
  CheckInIdConflictError,
  DisclaimerAlreadyPostedError,
  PhotoInUseError,
  PhotoNotUploadedError,
  PhotoNotYoursError,
  SportNotListedError,
  SquadNotJoinedError,
} from '../../errors.js';
import type {
  CheckInStore,
  Clock,
  MemberCalendar,
  PhotoFiles,
  SportList,
  SquadMembership,
} from '../../ports.js';

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
  {
    store,
    membership,
    photos,
    sports,
    calendarOf,
    clock,
  }: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly photos: PhotoFiles;
    readonly sports: SportList;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  { id, member, draft }: SaveCheckInInput,
): Promise<SavedCheckIn> {
  const checkIn = recordFromDraft(draft, { id, member });
  const retry = await asRetry(store, checkIn);
  if (retry !== undefined) return retry;

  checkCheckInTime(checkIn, { now: clock(), timeZone: (await calendarOf(member))?.timeZone });
  const joined = await membership.squadIdsOf(member);
  const notJoined = checkIn.audience.find((squad) => !joined.has(squad));
  if (notJoined !== undefined) throw new SquadNotJoinedError(notJoined);
  await checkPhotos(photos, checkIn);
  if (checkIn.kind === 'trained') await checkSport(sports, checkIn.training.sport);

  const outcome = await store.insert(checkIn);
  if (outcome.saved) return { checkIn, created: true };
  // A save of the same id may have finished while this one ran.
  const overlapping = await asRetry(store, checkIn);
  if (overlapping !== undefined) return overlapping;
  if (outcome.taken === 'dailyDisclaimer') throw new DisclaimerAlreadyPostedError(checkIn.day);
  if (outcome.taken === 'photo') throw new PhotoInUseError();
  throw new CheckInIdConflictError(id);
}

/** A listed sport, or 其他. */
export async function checkSport(sports: SportList, sport: string): Promise<void> {
  if (sport !== CUSTOM_SPORT && !(await sports.isListed(sport))) {
    throw new SportNotListedError(sport);
  }
}

/** Each photo is the member's own and already uploaded. */
async function checkPhotos(files: PhotoFiles, checkIn: CheckInRecord): Promise<void> {
  const paths = photosOf(checkIn).map(({ path }) => path);
  const notYours = paths.find((path) => !isOwnPhoto(path, checkIn.member));
  if (notYours !== undefined) throw new PhotoNotYoursError(notYours);
  const uploaded = await Promise.all(paths.map((path) => files.exists(path)));
  const missing = paths.find((_path, index) => uploaded[index] !== true);
  if (missing !== undefined) throw new PhotoNotUploadedError(missing);
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
