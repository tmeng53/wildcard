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
import {
  AlreadyTrainedError,
  CheckInIdConflictError,
  PhotoInUseError,
  WorkoutAlreadyPostedError,
  SquadNotJoinedError,
} from '../../errors.js';
import type {
  CheckInStore,
  Clock,
  MemberCalendar,
  PhotoFiles,
  SportList,
  SquadMembership,
  WeeklyPlanStore,
} from '../../ports.js';
import { checkPhotos } from '../check-photos.js';
import { checkSport } from '../check-sport.js';
import { planTrainedDay } from '../weekly-plans.js';

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
 * before the time checks, so a late retry of a saved check-in still succeeds. A 练了 on a day the
 * member's plan has as a rest day makes it a training day of that sport, on a retry too, so a
 * save that stopped between the two still ends with both.
 */
export async function saveCheckIn(
  {
    store,
    membership,
    photos,
    sports,
    plans,
    calendarOf,
    clock,
  }: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly photos: PhotoFiles;
    readonly sports: SportList;
    readonly plans: WeeklyPlanStore;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  { id, member, draft }: SaveCheckInInput,
): Promise<SavedCheckIn> {
  const checkIn = recordFromDraft(draft, { id, member });
  const saved = await insertCheckIn(
    { store, membership, photos, sports, calendarOf, clock },
    checkIn,
  );
  if (saved.checkIn.kind === 'trained') {
    await planTrainedDay(
      { store: plans },
      {
        member,
        day: saved.checkIn.day,
        training: saved.checkIn.training,
        checkIn: saved.checkIn.id,
      },
    );
  }
  return saved;
}

async function insertCheckIn(
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
  checkIn: CheckInRecord,
): Promise<SavedCheckIn> {
  const { id, member } = checkIn;
  const retry = await asRetry(store, checkIn);
  if (retry !== undefined) return retry;

  const postedDay = checkCheckInTime(checkIn, {
    now: clock(),
    timeZone: (await calendarOf(member))?.timeZone,
  });
  const joined = await membership.squadIdsOf(member);
  const notJoined = checkIn.audience.find((squad) => !joined.has(squad));
  if (notJoined !== undefined) throw new SquadNotJoinedError(notJoined);
  await checkPhotos(photos, {
    member: checkIn.member,
    paths: photosOf(checkIn).map(({ path }) => path),
  });
  if (checkIn.kind === 'trained') await checkSport(sports, checkIn.training.sport);

  if (checkIn.kind === 'disclaimer') await checkNotTrained(store, checkIn);

  const saving: CheckInRecord = { ...checkIn, postedDay };
  const outcome = await store.insert(saving);
  if (outcome.saved) return { checkIn: saving, created: true };
  // A save of the same id may have finished while this one ran.
  const overlapping = await asRetry(store, checkIn);
  if (overlapping !== undefined) return overlapping;
  if (outcome.taken === 'photo') throw new PhotoInUseError();
  if (outcome.taken === 'workout') throw new WorkoutAlreadyPostedError();
  throw new CheckInIdConflictError(id);
}

/**
 * A 请假条 is for a day the member hasn't trained on, the day it counts for, so a 补打卡 follows
 * the same rule as today's. (A 练了 after a 请假条 is fine: the app stamps it 销假.)
 */
async function checkNotTrained(store: CheckInStore, checkIn: CheckInRecord): Promise<void> {
  const sameDay = await store.listForMember({
    member: checkIn.member,
    from: checkIn.day,
    to: checkIn.day,
  });
  if (sameDay.some(({ kind }) => kind === 'trained')) throw new AlreadyTrainedError(checkIn.day);
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
