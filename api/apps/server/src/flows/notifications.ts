import type { CheckInRecord, CheckIns, Reacted } from '@wildcard/check-ins';
import { MemberId, type Push, type PushNotification } from '@wildcard/push';

import type { Log } from '../log.js';

// Who hears about what. A flow, since it joins two modules: check-ins say who sees a check-in,
// push reaches their phones. Notifications carry String Catalog keys, not words, so the copy is
// the app's. Sending never fails the request that caused it: a failure is logged and dropped.

interface Deps {
  readonly checkIns: CheckIns;
  readonly push: Push;
  readonly log: Log;
}

/**
 * Tells everyone who sees a new check-in about it, with the reaction buttons on the
 * notification. A teammate's later check-in that day replaces their earlier notification
 * instead of stacking up.
 */
export async function notifyTeammatesOfCheckIn(deps: Deps, checkIn: CheckInRecord): Promise<void> {
  await send(deps, {
    about: 'check-in',
    build: async () => ({
      members: await deps.checkIns.listTeammatesOf(checkIn),
      notification: {
        alert: { key: `push.checkIn.${checkIn.kind}` },
        category: `checkIn.${checkIn.kind}`,
        thread: `check-ins:${checkIn.day}`,
        collapseId: `check-in:${checkIn.member}:${checkIn.day}`,
        interruption: 'active',
        event: { type: 'checkIn', checkIn: checkIn.id, member: checkIn.member, kind: checkIn.kind },
      },
    }),
  });
}

/**
 * Tells a check-in's author about a new reaction on it, with how many it has. Each reaction
 * replaces the last one's notification, and only the first makes a sound.
 */
export async function notifyAuthorOfReaction(
  deps: Deps,
  { checkIn, reaction }: Reacted,
): Promise<void> {
  await send(deps, {
    about: 'reaction',
    build: async () => {
      const count = (
        await deps.checkIns.listReactions({ checkIn: checkIn.id, viewer: checkIn.member })
      ).length;
      return {
        members: [MemberId.parse(checkIn.member)],
        notification: {
          alert: { key: `push.reaction.${reaction.kind}`, args: [String(count)] },
          category: 'reaction',
          thread: `check-in:${checkIn.id}`,
          collapseId: `reactions:${checkIn.id}`,
          interruption: count <= 1 ? 'active' : 'passive',
          event: {
            type: 'reaction',
            checkIn: checkIn.id,
            member: reaction.member,
            kind: reaction.kind,
            count: String(count),
          },
        },
      };
    },
  });
}

async function send(
  { push, log }: Deps,
  {
    about,
    build,
  }: {
    readonly about: string;
    readonly build: () => Promise<{
      readonly members: readonly string[];
      readonly notification: PushNotification;
    }>;
  },
): Promise<void> {
  try {
    const { members, notification } = await build();
    const outcome = await push.notifyMembers({
      members: members.map((member) => MemberId.parse(member)),
      notification,
    });
    if (outcome.failures.length > 0) {
      log.error('push failed', { about, failures: outcome.failures });
    }
  } catch (error) {
    log.error('push failed', { about, error });
  }
}
