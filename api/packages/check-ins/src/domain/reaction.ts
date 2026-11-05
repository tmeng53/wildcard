import { z } from 'zod';

import type { CheckInRecord, MemberId, SquadId } from './check-in.js';

const graphemes = new Intl.Segmenter('en', { granularity: 'grapheme' });

/** No emoji in Unicode takes more code points than this; it keeps a stored one small. */
const MAX_CODE_POINTS = 16;

/**
 * Whether `text` is one emoji: one grapheme whose first code point is an emoji that shows as
 * one by itself, or is followed by more (a variation selector, a keycap, a skin tone, a joiner).
 * So ❤️, 1️⃣, flags and family emoji are, and a bare digit or `#` is not.
 */
function isOneEmoji(text: string): boolean {
  // Code points, not graphemes: what a joiner or a selector follows is what matters here.
  const codePoints = Array.from(text);
  const [first] = codePoints;
  if (first === undefined || codePoints.length > MAX_CODE_POINTS) return false;
  if ([...graphemes.segment(text)].length !== 1) return false;
  return (
    /\p{Emoji}/u.test(first) && (/\p{Emoji_Presentation}/u.test(first) || codePoints.length > 1)
  );
}

/**
 * The reaction a teammate leaves on a check-in: any one emoji, like iMessage's (Tracy,
 * 2026-10-20). A member leaves at most one per check-in and can change it.
 */
export const Emoji = z.string().refine(isOneEmoji, 'Not one emoji').brand<'Emoji'>();
export type Emoji = z.infer<typeof Emoji>;

/** A member's reaction on a check-in. */
export interface Reaction {
  readonly member: MemberId;
  readonly emoji: Emoji;
  readonly reactedAt: Date;
}

/** What saving a reaction did: a new one, a different one in place of the member's last, or nothing. */
export type SaveOutcome = 'created' | 'changed' | 'unchanged';

/**
 * The squads through which `viewer` sees a check-in: those it went to that both they and its
 * author are in now (leaving a squad takes your check-ins out of it, as in its feed). Empty when
 * they can't see it, unless it is their own. Only reactions from members of these squads are
 * shown to them, so a reaction never reveals a squad they aren't in.
 */
export function sharedSquads(
  checkIn: Pick<CheckInRecord, 'audience'>,
  {
    viewerSquads,
    authorSquads,
  }: {
    readonly viewerSquads: ReadonlySet<SquadId>;
    readonly authorSquads: ReadonlySet<SquadId>;
  },
): SquadId[] {
  return checkIn.audience.filter((squad) => viewerSquads.has(squad) && authorSquads.has(squad));
}
