import { MemberId, SquadId, type CoachWakes } from '@wildcard/coach';
import { MemberId as SquadMember, type Squads } from '@wildcard/squads';
import { z } from 'zod';

import { CoachPreviewDeliverNotSelfError, CoachPreviewNoSquadError } from '../../errors.js';
import { adminTool } from '../admin-tool.js';

// What the coach would write to one member today, to test a prompt or a coach without waiting
// for the morning or bending the limits (Tracy, 2026-11-08: preview only, nothing saved or sent).
// With deliver, the note also really reaches the member (Tracy, 2026-11-09: 要让他真的发给我自己).

interface CoachPreviewToolDependencies {
  readonly preview: CoachWakes['preview'];
  readonly squads: Pick<Squads, 'listMine'>;
}

/** `preview_coach_daily`: runs today's daily wake for one member and shows what it would do. */
export function previewCoachDaily({ preview, squads }: CoachPreviewToolDependencies) {
  return adminTool({
    name: 'preview_coach_daily',
    title: 'Preview the coach’s day for one member',
    description:
      'Runs today’s daily wake of the member’s squad coach now, for that member alone, and ' +
      'returns what it would do: the 战术板 line, the morning note (便条) with its day’s challenge, ' +
      'the gift and line it would give, the memory files it would change and every tool call. ' +
      'Nothing is saved or sent: no card, notice or push reaches anyone, and the one-note-a-day ' +
      'and one-gift-a-week limits are untouched. It calls the model once, so it costs like a ' +
      'wake (`costMicros`, millionths of a US dollar), counted against the squad’s daily cap; ' +
      '`ran: false` says why it didn’t run (no coach, off duty). Works while coaching is off. ' +
      'With `deliver: true`, only for yourself as the member, the note and its challenge are ' +
      'saved as your real note for today: it is pushed and shows on your coach page at the next ' +
      'run of the coach job (every 10 minutes) once your clock is past the morning note hour, and ' +
      'it is your one note for the day, so that morning’s wake writes you none. `delivered` says ' +
      'whether it was saved (false when you already have today’s). The 战术板 line and the gift ' +
      'stay a preview.',
    changes: true,
    input: z.strictObject({
      member: MemberId.describe('The member’s id.'),
      deliver: z
        .boolean()
        .optional()
        .describe('Also send the note to you as today’s, for real; you must be the member.'),
    }),
    run: async ({ member, deliver }, { admin }) => {
      if (deliver === true && String(member) !== String(admin))
        throw new CoachPreviewDeliverNotSelfError();
      const [squad] = await squads.listMine(SquadMember.parse(member));
      if (squad === undefined) throw new CoachPreviewNoSquadError();
      return {
        version: 1,
        ...(await preview({
          squad: SquadId.parse(squad.id),
          member,
          ...(deliver === undefined ? {} : { deliver }),
        })),
      };
    },
  });
}
