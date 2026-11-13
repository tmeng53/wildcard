import { typedText } from '@wildcard/typed-text';
import { z } from 'zod';

import type { MemberId, SquadId, SquadName } from './squad.js';

export const JoinRequestId = z.uuid().brand<'JoinRequestId'>();
export type JoinRequestId = z.infer<typeof JoinRequestId>;

/** The most characters a request's note may have. */
export const JOIN_NOTE_MAX_CHARACTERS = 30;

/** What the member writes the captain with their request (备注): one line, up to 30 characters. */
export const JoinNote = typedText({
  max: JOIN_NOTE_MAX_CHARACTERS,
  oneLine: true,
  description: 'A line to the captain (备注): trimmed, 1 to 30 characters on one line.',
}).brand<'JoinNote'>();
export type JoinNote = z.infer<typeof JoinNote>;

/**
 * Whether a squad that never set its switch needs the captain's OK to join (Tracy, 2026-11-12:
 * on unless the captain turns it off).
 */
export const JOIN_APPROVAL_DEFAULT = true;

/**
 * How a request to join ended: the captain `approved` or `declined` it, the member `withdrew` it
 * (or asked another squad), or it was `cancelled` because they got into a squad another way or
 * the squad ended.
 */
export type JoinRequestAnswerKind = 'approved' | 'declined' | 'withdrawn' | 'cancelled';

/** A member asking to join a squad (入队申请); waiting while it has no `answer`. */
export interface JoinRequest {
  readonly id: JoinRequestId;
  readonly squad: SquadId;
  readonly squadName: SquadName;
  readonly member: MemberId;
  readonly note?: JoinNote;
  readonly askedAt: Date;
  readonly answer?: { readonly kind: JoinRequestAnswerKind; readonly at: Date };
}
