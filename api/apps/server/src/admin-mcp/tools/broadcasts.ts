import {
  BroadcastId,
  BroadcastValue,
  MemberId,
  isRunning,
  type Broadcast,
  type Broadcasts,
} from '@wildcard/notices';
import { UnlockItemMissingError, type UnlocksAdmin } from '@wildcard/unlocks';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// Broadcasts (群发通知): a notice written once for every member, each told it on their first open
// of the app while it runs, with an optional button to a place in the app and optional gifts, unlocked
// for each member when they are told. A holiday is one of these.

interface BroadcastToolDependencies {
  readonly broadcasts: Broadcasts;
  readonly unlocks: Pick<UnlocksAdmin, 'rules'>;
  readonly clock: () => Date;
}

const shown = (broadcast: Broadcast, now: Date) => ({
  id: broadcast.id,
  ...broadcast.value,
  running: isRunning(broadcast.value, now),
  by: broadcast.by,
  savedAt: broadcast.savedAt.toISOString(),
});

/** `list_broadcasts`: every broadcast as it is now. */
export function listBroadcasts({ broadcasts, clock }: BroadcastToolDependencies) {
  return adminTool({
    name: 'list_broadcasts',
    title: 'List the broadcasts',
    description:
      'Shows every broadcast (群发通知) as it says now, the latest saved first, with whether it ' +
      'is running (members who open the app now are told it).',
    changes: false,
    input: z.strictObject({}),
    run: async () => {
      const now = clock();
      return { version: 1, broadcasts: (await broadcasts.list()).map((each) => shown(each, now)) };
    },
  });
}

/** `put_broadcast`: writes a broadcast, or changes one. */
export function putBroadcast({ broadcasts, unlocks, clock }: BroadcastToolDependencies) {
  return adminTool({
    name: 'put_broadcast',
    title: 'Write or change a broadcast',
    description:
      'Writes a broadcast (群发通知) to every member, or changes the one with this id: each ' +
      'member is told it once, on their first open of the app from startsAt until endsAt, and ' +
      'it then stays in their 通知. Words are in Simplified Chinese, English and Traditional ' +
      'Chinese. A change (such as a typo fix) shows to members already told; members told it ' +
      'are never told again, so a new message needs a new id. Gifts are unlocked for each ' +
      'member when they are told, quietly (the words say the 商店街 has something new); each ' +
      'must have an unlock rule (get_unlock_rules). Returns the broadcast now, and whether this save changed it.',
    changes: true,
    input: z.strictObject({
      id: BroadcastId.describe('A short slug of your choosing, such as `thanksgiving-soon`.'),
      broadcast: BroadcastValue,
    }),
    run: async ({ id, broadcast }, { admin }) => {
      const ruled = new Set((await unlocks.rules()).map(({ kind, id: item }) => `${kind}:${item}`));
      for (const { kind, id: item } of broadcast.gifts) {
        if (!ruled.has(`${kind}:${item}`)) throw new UnlockItemMissingError(`${kind}:${item}`);
      }
      const saved = await broadcasts.put({
        id,
        value: broadcast,
        by: MemberId.parse(admin),
      });
      return { version: 1, changed: saved.changed, broadcast: shown(saved.broadcast, clock()) };
    },
  });
}

export const broadcastTools = (deps: BroadcastToolDependencies) => [
  listBroadcasts(deps),
  putBroadcast(deps),
];
