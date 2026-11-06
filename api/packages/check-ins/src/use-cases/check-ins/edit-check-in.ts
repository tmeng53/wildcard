import {
  isSameCheckIn,
  photosOf,
  recordFromDraft,
  type CheckInEdit,
  type CheckInId,
  type CheckInRecord,
  type MemberId,
} from '../../domain/check-in.js';
import type { PhotoRef } from '../../domain/photos.js';
import {
  CheckInKindChangedError,
  CheckInNotFoundError,
  NotYourCheckInError,
  PhotoInUseError,
  WorkoutAlreadyPostedError,
} from '../../errors.js';
import type {
  CheckInStore,
  PhotoFiles,
  SportList,
  SquadMembership,
  WeeklyPlanStore,
} from '../../ports.js';
import { checkPhotos } from '../check-photos.js';
import { checkSport } from '../check-sport.js';
import { planTrainedDay } from '../weekly-plans.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';

interface Deps {
  readonly store: CheckInStore;
  readonly membership: SquadMembership;
  readonly photos: PhotoFiles;
  readonly sports: SportList;
  readonly plans: WeeklyPlanStore;
}

/**
 * The member's own check-in under `id`. Throws `NotYourCheckInError` for a teammate's they can
 * see, and `CheckInNotFoundError` for one they can't.
 */
async function ownCheckIn(
  deps: Deps,
  { id, member }: { readonly id: CheckInId; readonly member: MemberId },
): Promise<CheckInRecord | undefined> {
  const saved = await deps.store.find(id);
  if (saved === undefined || saved.member === member) return saved;
  await findVisibleCheckIn(deps, { id, viewer: member });
  throw new NotYourCheckInError();
}

/**
 * Replaces the member's own check-in's fields and photos with `edit`, keeping its kind, day,
 * time and audience. The same contents again change nothing, so a retry is safe. A photo it
 * keeps keeps its saved size; a new one must be the member's own and uploaded. A sport is
 * checked against the list only when it changes, so a post of a sport since retired can still
 * be edited. Photos the edit leaves out are deleted. Throws `CheckInNotFoundError` for a check-in
 * that is gone.
 */
export async function editCheckIn(
  deps: Deps,
  {
    id,
    member,
    edit,
  }: { readonly id: CheckInId; readonly member: MemberId; readonly edit: CheckInEdit },
): Promise<CheckInRecord> {
  const saved = await ownCheckIn(deps, { id, member });
  if (saved === undefined) throw new CheckInNotFoundError(id);
  if (saved.kind !== edit.kind) throw new CheckInKindChangedError(saved.kind);
  const kept = new Map(photosOf(saved).map((photo) => [photo.path, photo] as const));
  const edited = withPhotos(
    {
      ...recordFromDraft(
        { ...edit, day: saved.day, createdAt: saved.createdAt, audience: [...saved.audience] },
        { id, member },
      ),
      // An edit keeps the day it was posted on, as it keeps the day it counts for.
      ...(saved.postedDay === undefined ? {} : { postedDay: saved.postedDay }),
    },
    (photos) => photos.map((photo) => kept.get(photo.path) ?? photo),
  );
  if (isSameCheckIn(saved, edited)) {
    // A retry after Storage failed: the edit is saved, so finish taking its photos off.
    await deleteDroppedPhotos(deps, saved.id);
    return saved;
  }

  const added = photosOf(edited).filter(({ path }) => !kept.has(path));
  await checkPhotos(deps.photos, { member, paths: added.map(({ path }) => path) });
  if (
    edited.kind === 'trained' &&
    saved.kind === 'trained' &&
    (edited.training.sport !== saved.training.sport ||
      edited.training.customSport !== saved.training.customSport)
  ) {
    await checkSport(deps.sports, edited.training.sport);
  }
  const outcome = await deps.store.update(edited);
  if (!outcome.saved) {
    throw outcome.taken === 'workout' ? new WorkoutAlreadyPostedError() : new PhotoInUseError();
  }
  if (edited.kind === 'trained') {
    await planTrainedDay(
      { store: deps.plans },
      { member, day: edited.day, training: edited.training },
    );
  }
  await deleteDroppedPhotos(deps, edited.id);
  return edited;
}

/**
 * Deletes the member's own check-in, with its photos, reactions, comments and log: the photo
 * files first, so a retry after a failure finishes the job. One that is gone already is a retry:
 * ids are random, so saying so tells nobody anything.
 */
export async function deleteCheckIn(
  deps: Deps,
  { id, member }: { readonly id: CheckInId; readonly member: MemberId },
): Promise<void> {
  const saved = await ownCheckIn(deps, { id, member });
  if (saved === undefined) return;
  // Every photo it ever had, in case an edit's Storage delete failed before.
  await deps.photos.delete(await deps.store.photoHistory(saved.id));
  await deps.store.remove(id);
}

/** The record with its photos mapped, left out when there are none. */
function withPhotos(
  record: CheckInRecord,
  map: (photos: readonly PhotoRef[]) => PhotoRef[],
): CheckInRecord {
  const fields = <T extends { readonly photos?: readonly PhotoRef[] | undefined }>(entry: T): T =>
    entry.photos === undefined ? entry : { ...entry, photos: map(entry.photos) };
  switch (record.kind) {
    case 'trained':
      return { ...record, training: fields(record.training) };
    case 'healthyMeal':
    case 'cheatMeal':
      return { ...record, meal: fields(record.meal) };
    case 'disclaimer':
      return { ...record, disclaimer: fields(record.disclaimer) };
  }
}

/**
 * Deletes from Storage every photo the check-in had in an earlier version and has no more, so
 * an edit whose delete failed is finished by the next try. Deleting a file already gone is
 * fine.
 *
 * The history is read before the post as it is now, never this request's copy of it: a photo
 * enters the history in the same transaction that puts it on the post, so one another edit
 * saved meanwhile is either on the post as read, or not yet in the history read.
 */
async function deleteDroppedPhotos(deps: Deps, id: CheckInId): Promise<void> {
  const history = await deps.store.photoHistory(id);
  const now = await deps.store.find(id);
  const left = new Set<string>(now === undefined ? [] : photosOf(now).map(({ path }) => path));
  const dropped = history.filter((path) => !left.has(path));
  if (dropped.length > 0) await deps.photos.delete(dropped);
}
