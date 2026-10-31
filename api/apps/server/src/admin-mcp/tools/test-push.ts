import { MemberId as PushMember, type Push } from '@wildcard/push';
import { MemberId as SquadMember, type Squads } from '@wildcard/squads';
import { SquadId, latestAwardedWeek } from '@wildcard/weekly-awards';
import { z } from 'zod';

import { TestPushNoSquadError } from '../../errors.js';
import { dailyProgressNotification } from '../../flows/daily-progress-push.js';
import { awardsReadyNotification } from '../../flows/weekly-awards.js';
import { adminTool } from '../admin-tool.js';

// A push to the admin's own phones, built by the same code as the real one, so an admin can see
// on a phone what members get and whether sending works at all, without waiting for 6pm or Sunday.

interface TestPushToolDependencies {
  readonly push: Push;
  readonly squads: Squads;
  readonly clock: () => Date;
}

/** The kinds of push a test can be: the daily push, plain or naming a 拍一拍, and the awards'. */
const TestPushKind = z.enum(['dailyProgress', 'poke', 'weeklyAwards']);

/** The teammate a test 拍一拍 names, since nobody really sent one. */
const SAMPLE_POKER = '测试队友';

/** `send_test_push`: sends the admin one push of a kind, to their own phones only. */
export function sendTestPush({ push, squads, clock }: TestPushToolDependencies) {
  return adminTool({
    name: 'send_test_push',
    title: 'Send yourself a test push',
    description:
      'Sends one push notification to your own phones only, built as the real one: ' +
      '`dailyProgress` (the 6pm push, with sample counts), `poke` (the 6pm push naming a ' +
      'teammate who patted you) or `weeklyAwards` (the 战报 is ready, for your squad’s latest ' +
      'week). Nobody else gets it, and the daily push still comes as usual. Returns how many ' +
      'phones it reached: `off` above 0 means the server has no APNs key; `phones` 0 means the ' +
      'app hasn’t registered one (allow notifications after a check-in); `failures` gives ' +
      'Apple’s reasons.',
    changes: true,
    input: z.strictObject({ kind: TestPushKind }),
    run: async ({ kind }, { admin }) => {
      const [squad] = await squads.listMine(SquadMember.parse(admin));
      if (squad === undefined) throw new TestPushNoSquadError();
      const now = clock();
      const notification =
        kind === 'weeklyAwards'
          ? awardsReadyNotification(SquadId.parse(squad.id), latestAwardedWeek(now))
          : dailyProgressNotification({
              day: now.toISOString().slice(0, 10),
              squad: squad.id,
              squadWeek: { trainedDays: 3, plannedDays: 5 },
              received: kind === 'poke' ? new Map([['poke', new Set([SAMPLE_POKER])]]) : new Map(),
              named: kind === 'poke' ? { kind: 'poke', nickname: SAMPLE_POKER } : undefined,
            });
      const outcome = await push.notifyMembers({
        members: [PushMember.parse(admin)],
        notification,
      });
      return {
        version: 1,
        kind,
        phones: outcome.sent + outcome.off + outcome.gone + outcome.failures.length,
        sent: outcome.sent,
        off: outcome.off,
        gone: outcome.gone,
        failures: outcome.failures.map((failure) =>
          failure instanceof Error ? failure.message : 'unknown failure',
        ),
      };
    },
  });
}

export const testPushTools = (deps: TestPushToolDependencies) => [sendTestPush(deps)];
