import type { MemberId, SquadId } from '../domain/check-in.js';
import { TrainedWithNotSquadmateError } from '../errors.js';
import type { SquadMembership } from '../ports.js';

/**
 * Each member a 训练 names it was done with is someone else in a squad it is shared to, now, and
 * the 训练 is in those squads' 动态 (`inFeed`): one only recorded names no one, since the
 * squadmates named couldn't see it. Only `added` are checked: a teammate tagged before who has
 * since left stays on the post.
 */
export async function checkTrainedWith(
  membership: SquadMembership,
  {
    member,
    audience,
    inFeed,
    added,
  }: {
    readonly member: MemberId;
    readonly audience: readonly SquadId[];
    readonly inFeed: boolean;
    readonly added: readonly MemberId[];
  },
): Promise<void> {
  if (added.length === 0) return;
  const mates =
    !inFeed || audience.length === 0 ? new Set() : await membership.membersOfAny(audience);
  const stranger = added.find((each) => each === member || !mates.has(each));
  if (stranger !== undefined) throw new TrainedWithNotSquadmateError(stranger);
}
