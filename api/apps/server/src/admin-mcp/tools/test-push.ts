import {
  MemberId as CheckInMember,
  SquadId as CheckInSquad,
  type CheckIns,
} from '@wildcard/check-ins';
import type { Members } from '@wildcard/members';
import { MemberId as PushMember, type Push } from '@wildcard/push';
import { MemberId as SquadMember, type Squads } from '@wildcard/squads';
import { SquadId, latestAwardedWeek } from '@wildcard/weekly-awards';
import { z } from 'zod';

import { TestPushNoSquadError } from '../../errors.js';
import { dailyProgressNotification, roomForToday } from '../../flows/daily-progress-push.js';
import { pushToday } from '../../flows/daily-push-today.js';
import { awardsReadyNotification } from '../../flows/weekly-awards.js';
import { adminTool } from '../admin-tool.js';

// A push to the admin's own phones, built by the same code as the real one, so an admin can see
// on a phone what members get and whether sending works at all, without waiting for 6pm or Sunday.

interface TestPushToolDependencies {
  readonly push: Push;
  readonly squads: Squads;
  /** The squad's real day, for the long-press view, as the 6pm push carries it. */
  readonly checkIns: Pick<CheckIns, 'squadToday' | 'listForSquad'>;
  readonly members: Pick<Members, 'squadmates'>;
  readonly clock: () => Date;
}

/** The kinds of push a test can be: the daily push, plain or naming a 拍一拍, and the awards'. */
const TestPushKind = z.enum(['dailyProgress', 'poke', 'weeklyAwards']);

/** The teammate a test 拍一拍 names, since nobody really sent one. */
const SAMPLE_POKER = '测试队友';

/** `send_test_push`: sends the admin one push of a kind, to their own phones only. */
export function sendTestPush({ push, squads, checkIns, members, clock }: TestPushToolDependencies) {
  return adminTool({
    name: 'send_test_push',
    title: 'Send yourself a test push',
    description:
      'Sends one push notification to your own phones only, built as the real one: ' +
      '`dailyProgress` (the 6pm push, with sample counts), `poke` (the 6pm push naming a ' +
      'teammate who patted you) or `weeklyAwards` (the 战报 is ready, for your squad’s latest ' +
      'week). Nobody else gets it, and it never replaces or hides the real push. Returns how many ' +
      'phones it reached: `off` above 0 means the server has no APNs key; `phones` 0 means the ' +
      'app hasn’t registered one (allow notifications after a check-in); `failures` gives ' +
      'Apple’s reasons.',
    changes: true,
    input: z.strictObject({ kind: TestPushKind }),
    run: async ({ kind }, { admin }) => {
      const [squad] = await squads.listMine(SquadMember.parse(admin));
      if (squad === undefined) throw new TestPushNoSquadError();
      const now = clock();
      const built =
        kind === 'weeklyAwards'
          ? awardsReadyNotification(SquadId.parse(squad.id), latestAwardedWeek(now))
          : await dailyProgress(kind, { admin, squad: squad.id, now });
      // Its own collapse id, so on the phone it never replaces the real push of the day or week,
      // nor is replaced by it.
      const notification = { ...built, collapseId: `test-${kind}-${String(now.getTime())}` };
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

  /** The 6pm push with sample counts and sender, carrying the squad's real day as the real one does. */
  async function dailyProgress(
    kind: 'dailyProgress' | 'poke',
    { admin, squad, now }: { readonly admin: string; readonly squad: string; readonly now: Date },
  ) {
    const told = {
      day: now.toISOString().slice(0, 10),
      squad,
      squadWeek: { trainedDays: 3, plannedDays: 5 },
      received:
        kind === 'poke'
          ? new Map([['poke', new Set([SAMPLE_POKER])]])
          : new Map<string, Set<string>>(),
      named: kind === 'poke' ? { kind: 'poke' as const, nickname: SAMPLE_POKER } : undefined,
    };
    const squadId = CheckInSquad.parse(squad);
    const today = await checkIns.squadToday({ viewer: CheckInMember.parse(admin), squad: squadId });
    return dailyProgressNotification({
      ...told,
      // Without it the long-press view has nothing to show; a failure still sends the words.
      today: await pushToday(
        { checkIns, members },
        { viewer: admin, squad: squadId, today, pokers: [], bytes: roomForToday(told) },
      ).catch(() => undefined),
    });
  }
}

export const testPushTools = (deps: TestPushToolDependencies) => [sendTestPush(deps)];
