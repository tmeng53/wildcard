import { MemberId, SquadId, type CoachWakes } from '@wildcard/coach';
import { MemberId as SquadMember, type Squads } from '@wildcard/squads';
import { z } from 'zod';

import { CoachPreviewNoSquadError } from '../../errors.js';
import { adminTool } from '../admin-tool.js';

// What the coach would write to one member today, to test a prompt or a coach without waiting
// for the morning or bending the limits (Tracy, 2026-11-08: preview only, nothing saved or sent).

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
      '`ran: false` says why it didn’t run (no coach, off duty). Works while coaching is off.',
    changes: true,
    input: z.strictObject({ member: MemberId.describe('The member’s id.') }),
    run: async ({ member }) => {
      const [squad] = await squads.listMine(SquadMember.parse(member));
      if (squad === undefined) throw new CoachPreviewNoSquadError();
      return { version: 1, ...(await preview({ squad: SquadId.parse(squad.id), member })) };
    },
  });
}
