import {
  FeedbackId,
  MemberId as FeedbackMember,
  type Adoption,
  type AdoptionKind,
  type FeedbackAdoptions,
} from '@wildcard/feedback';
import { MemberId as NoticeMember, type Notices } from '@wildcard/notices';
import { EventName, MemberId as RewardMember, type Given, type Rewards } from '@wildcard/unlocks';

// Thanks for feedback we used (Tracy, 2026-11-08): an admin, having checked that a bug is real or
// that an idea's change merged, adopts the message; its sender then gets whatever the
// `<kind>-adopted` event's triggers give (a piece, a badge, a 高级券: data, not code) and a notice.
// It spans the feedback, unlocks and notices modules, so it lives here.

/** The event each kind of adoption sets off, which the rewards' `event` triggers name. */
export function adoptionEvent(kind: AdoptionKind): EventName {
  return EventName.parse(`${kind}-adopted`);
}

/**
 * Adopts message `feedback` as `kind` for `admin` and thanks its sender, in the caller's
 * transaction. Adopting it again keeps the first adoption and gives nothing more: the same
 * message never thanks twice. Answers with the adoption and what this call gave.
 */
export function adoptFeedback(deps: {
  readonly feedback: FeedbackAdoptions;
  readonly rewards: Pick<Rewards, 'happened'>;
  readonly notices: Pick<Notices, 'tell'>;
}) {
  return async (input: {
    readonly feedback: string;
    readonly kind: AdoptionKind;
    readonly admin: string;
  }): Promise<{
    readonly adoption: Adoption;
    readonly fresh: boolean;
    readonly given: readonly Given[];
  }> => {
    const { adoption, fresh } = await deps.feedback.adopt({
      id: FeedbackId.parse(input.feedback),
      kind: input.kind,
      admin: FeedbackMember.parse(input.admin),
    });
    if (!fresh) return { adoption, fresh, given: [] };
    const given = await deps.rewards.happened({
      member: RewardMember.parse(adoption.member),
      event: adoptionEvent(adoption.kind),
      id: adoption.feedback,
      at: adoption.at,
    });
    await deps.notices.tell([
      {
        member: NoticeMember.parse(adoption.member),
        kind: 'thanks',
        subject: { version: 1, feedback: adoption.feedback, adopted: adoption.kind },
      },
    ]);
    return { adoption, fresh, given };
  };
}
