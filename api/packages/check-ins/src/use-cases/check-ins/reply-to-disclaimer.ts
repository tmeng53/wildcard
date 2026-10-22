import type { CheckInId, MemberId } from '../../domain/check-in.js';
import type { SaveOutcome } from '../../domain/reaction.js';
import type { Reply, ReplyKind } from '../../domain/reply.js';
import { NotADisclaimerError, OwnDisclaimerReplyError } from '../../errors.js';
import type { CheckInStore, Clock, ReplyStore, SquadMembership } from '../../ports.js';
import { findVisibleCheckIn } from './find-visible-check-in.js';

export interface ReplyToDisclaimerInput {
  readonly checkIn: CheckInId;
  readonly member: MemberId;
  readonly kind: ReplyKind;
}

export interface Replied {
  readonly reply: Reply;
  readonly outcome: SaveOutcome;
}

/**
 * Leaves the member's reply on a teammate's 请假条, in place of any they left before. The same
 * reply again changes nothing (not even its time), so a retry is safe. Throws
 * `CheckInNotFoundError` for a check-in they can't see, `NotADisclaimerError` for one that isn't a
 * 请假条 and `OwnDisclaimerReplyError` for their own.
 */
export async function replyToDisclaimer(
  {
    store,
    membership,
    replies,
    clock,
  }: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly replies: ReplyStore;
    readonly clock: Clock;
  },
  { checkIn: id, member, kind }: ReplyToDisclaimerInput,
): Promise<Replied> {
  const { checkIn } = await findVisibleCheckIn({ store, membership }, { id, viewer: member });
  if (checkIn.kind !== 'disclaimer') throw new NotADisclaimerError(id);
  if (checkIn.member === member) throw new OwnDisclaimerReplyError();
  const asked = { member, kind, repliedAt: clock() };
  const outcome = await replies.save(id, asked);
  // Unchanged keeps the time it was first left.
  const saved = (await replies.list(id)).find((reply) => reply.member === member);
  // Taken off by a removal that ran at the same moment: answer with what was asked.
  return { reply: saved ?? asked, outcome };
}
