import { NICKNAME_MAX_CHARACTERS } from '@wildcard/members';
import { apnsPayload } from '@wildcard/push';
import { SquadId, WeekStart } from '@wildcard/weekly-awards';

import { dailyProgressNotification } from './flows/daily-progress-push.js';
import { awardsReadyNotification, awardsStuckNotification } from './flows/weekly-awards.js';
import type { PushCopyKey } from './push-copy.js';

const squad = SquadId.parse('6f1c2a5e-8d3b-4f7a-9c2e-1b4d5a6e7f80');
const week = WeekStart.parse('2026-10-19');
const day = '2026-10-23';
const mates = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'].map(
  (letter) => `00000000-0000-4000-8000-00000000000${letter}`,
);
/** The longest nickname a member can pick, in the widest characters. */
const longestNickname = '超'.repeat(NICKNAME_MAX_CHARACTERS);

/**
 * One APNs payload for every push the server sends, built by the flows themselves, with the
 * longest names they can carry: what the app's UI tests deliver to the simulator to look at the
 * real banner and tap it. `pnpm push-samples` in api/ writes them to
 * `ios/WildcardUITests/push-samples.json`; `push-copy.test.ts` fails while that copy is stale.
 */
export function pushSamples(): Record<PushCopyKey, unknown> {
  const daily = (named?: { readonly others: number }) =>
    dailyProgressNotification({
      day,
      squad,
      squadWeek: { trainedDays: 23, plannedDays: 40 },
      received: new Map([
        ['reaction', new Set(mates.slice(0, 3))],
        ...(named === undefined
          ? []
          : [['poke', new Set(mates.slice(0, named.others + 1))] as const]),
      ]),
      named: named === undefined ? undefined : { kind: 'poke', nickname: longestNickname },
    });
  return {
    'push.dailyProgress': apnsPayload(
      dailyProgressNotification({
        day,
        squad,
        squadWeek: { trainedDays: 0, plannedDays: 40 },
        received: new Map(),
      }),
    ),
    'push.dailyProgress.received': apnsPayload(daily()),
    'push.dailyProgress.poke': apnsPayload(daily({ others: 0 })),
    'push.dailyProgress.poke.more': apnsPayload(daily({ others: 7 })),
    'push.weeklyAwards.ready': apnsPayload(awardsReadyNotification(squad, week)),
    'push.weeklyAwards.stuck': apnsPayload(
      awardsStuckNotification({
        squad: { id: squad, name: '队'.repeat(20) },
        week,
        failures: {
          count: 12,
          lastError:
            '429 You exceeded your current quota, please check your plan and billing details.',
        },
      }),
    ),
  };
}

/** The samples as the committed file holds them. */
export const pushSamplesJson = () => `${JSON.stringify(pushSamples(), null, 2)}\n`;
