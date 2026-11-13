import { checkCheckInTime } from '../../domain/check-in-time.js';
import {
  isSameCheckIn,
  photosOf,
  recordFromDraft,
  trainedWithOf,
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
  SquadPlaceOf,
  SquadMembership,
  WeeklyPlanStore,
} from '../../ports.js';
import { checkPhotos } from '../check-photos.js';
import { checkSquadPlace } from '../check-place.js';
import { checkSport } from '../check-sport.js';
import { checkTrainedWith } from '../check-trained-with.js';
import { planRestDay, planTrainedDay } from '../weekly-plans.js';

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
 * before the time checks, so a late retry of a saved check-in still succeeds. A 训练 makes its
 * day in the member's plan show its sport when the plan had it as a rest day, named no sport or
 * named one the day's 训练 didn't log (`planTrainedDay`), on a retry too, so a save that stopped
 * between the two still ends with both. A 休息 makes its day a rest day the same way.
 */
export async function saveCheckIn(
  {
    store,
    membership,
    photos,
    sports,
    squadPlaceOf,
    plans,
    calendarOf,
    clock,
  }: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly photos: PhotoFiles;
    readonly sports: SportList;
    readonly squadPlaceOf?: SquadPlaceOf;
    readonly plans: WeeklyPlanStore;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  { id, member, draft }: SaveCheckInInput,
): Promise<SavedCheckIn> {
  const checkIn = recordFromDraft(draft, { id, member });
  const saved = await insertCheckIn(
    { store, membership, photos, sports, squadPlaceOf, calendarOf, clock },
    checkIn,
  );
  if (saved.checkIn.kind === 'trained') {
    await planTrainedDay(
      { store: plans, checkIns: store },
      {
        member,
        day: saved.checkIn.day,
        training: saved.checkIn.training,
        checkIn: saved.checkIn.id,
      },
    );
  }
  await planRestPost({ store, plans }, saved.checkIn);
  return saved;
}

/**
 * Makes a 休息's day a rest day in the member's plan, unless they trained that day: a 训练 after
 * the 休息 made it a training day, and a retry or an edit of the 休息 must not undo that.
 */
export async function planRestPost(
  { store, plans }: { readonly store: CheckInStore; readonly plans: WeeklyPlanStore },
  checkIn: CheckInRecord,
): Promise<void> {
  if (checkIn.kind !== 'disclaimer' || checkIn.disclaimer.restDay !== true) return;
  const sameDay = await store.listForMember({
    member: checkIn.member,
    from: checkIn.day,
    to: checkIn.day,
  });
  if (sameDay.some(({ kind }) => kind === 'trained')) return;
  await planRestDay({ store: plans }, { member: checkIn.member, day: checkIn.day });
}

async function insertCheckIn(
  {
    store,
    membership,
    photos,
    sports,
    squadPlaceOf,
    calendarOf,
    clock,
  }: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly photos: PhotoFiles;
    readonly sports: SportList;
    readonly squadPlaceOf?: SquadPlaceOf | undefined;
    readonly calendarOf: MemberCalendar;
    readonly clock: Clock;
  },
  drafted: CheckInRecord,
): Promise<SavedCheckIn> {
  const { id, member } = drafted;
  const joined = await membership.squadIdsOf(member);
  // A check-in made in a squad always goes to it: an empty audience (an older build's 仅自己可见,
  // which `recordFromDraft` takes off the feed) goes to the member's squads.
  const checkIn: CheckInRecord =
    drafted.audience.length === 0 ? { ...drafted, audience: [...joined] } : drafted;
  const retry = await asRetry(store, checkIn);
  if (retry !== undefined) return retry;

  const postedDay = checkCheckInTime(checkIn, {
    now: clock(),
    timeZone: (await calendarOf(member))?.timeZone,
  });
  const notJoined = checkIn.audience.find((squad) => !joined.has(squad));
  if (notJoined !== undefined) throw new SquadNotJoinedError(notJoined);
  await checkPhotos(photos, {
    member: checkIn.member,
    paths: photosOf(checkIn).map(({ path }) => path),
  });
  if (checkIn.kind === 'trained') await checkSport(sports, checkIn.training.sport);
  await checkTrainedWith(membership, {
    member,
    audience: checkIn.audience,
    inFeed: checkIn.inFeed,
    added: trainedWithOf(checkIn),
  });
  await checkSquadPlace(squadPlaceOf, checkIn);

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
 * the same rule as today's. (A 训练 after a 请假条 is fine: the app stamps it 销假.)
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
