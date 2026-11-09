import { randomUUID } from 'node:crypto';

import { AdminId } from '@wildcard/admins';
import { describe, expect, it } from 'vitest';

import { CoachPreviewDeliverNotSelfError, CoachPreviewNoSquadError } from '../../errors.js';
import { previewCoachDaily } from './coach-preview.js';

// Delivering a preview sends the coach's real note, so only to the admin asking (Tracy,
// 2026-11-09: 发给我自己). The guard runs before anything else, so no squad is needed here.
describe('preview_coach_daily', () => {
  const admin = AdminId.parse(randomUUID());
  let previews = 0;
  const tool = previewCoachDaily({
    preview: () => {
      previews += 1;
      return Promise.resolve({ ran: false, why: 'the squad has no coach' });
    },
    squads: { listMine: () => Promise.resolve([]) },
  });

  it('refuses to deliver to anyone but the admin asking', async () => {
    await expect(
      tool.run({ member: randomUUID(), deliver: true }, { admin }),
    ).rejects.toBeInstanceOf(CoachPreviewDeliverNotSelfError);
    expect(previews).toBe(0);
  });

  it('delivers to the admin themselves, and previews anyone without deliver', async () => {
    // Past the guard, each meets the next check: a member in no squad.
    await expect(tool.run({ member: admin, deliver: true }, { admin })).rejects.toBeInstanceOf(
      CoachPreviewNoSquadError,
    );
    await expect(tool.run({ member: randomUUID() }, { admin })).rejects.toBeInstanceOf(
      CoachPreviewNoSquadError,
    );
  });
});
