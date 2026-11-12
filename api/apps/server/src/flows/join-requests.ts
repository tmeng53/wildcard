import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import {
  MemberId as NoticeMember,
  SquadId as NoticeSquad,
  type NewNotice,
  type Notices,
} from '@wildcard/notices';
import {
  MemberId as PushMember,
  type EventValue,
  type Push,
  type PushNotification,
} from '@wildcard/push';
import type { JoinRequest, Squads } from '@wildcard/squads';

import type { Log } from '../log.js';
import { pushAlert } from '../push-copy.js';
import { noticeAlert } from './daily-progress-push.js';

// 入队申请 (Tracy, 2026-11-12): the captain is told someone asked to join, and the member is told
// once they are let in, each in their 通知 and by push. A decline is told only in the app, where
// the member reads their request again.

export interface JoinRequestNewsDependencies {
  readonly squads: Pick<Squads, 'captainOf'>;
  readonly members: Pick<Members, 'squadmates'>;
  readonly push: Pick<Push, 'settingsOf' | 'notifyMembers'>;
  readonly notices: Pick<Notices, 'tell'>;
  readonly log: Log;
}

/**
 * The captain's push about a request: 「小橘 申请加入小队」. Long-pressed, the app's own view
 * (the `joinRequest` category) shows the member's character, from `look`, with 拒绝 and 同意,
 * which answer it without opening the app.
 */
export function joinRequestNotification({
  request,
  nickname,
  look,
}: {
  readonly request: { readonly id: string; readonly squad: string; readonly member: string };
  readonly nickname: string;
  /** The member's character as `GET /me` sends it; not a squadmate yet, so the app has none. */
  readonly look?: EventValue | undefined;
}): PushNotification {
  return {
    alert: pushAlert('push.joinRequest', [nickname]),
    category: 'joinRequest',
    thread: `join-${request.squad}`,
    collapseId: `join-${request.id}`,
    interruption: 'active',
    event: {
      kind: 'joinRequest',
      squadId: request.squad,
      request: request.id,
      member: request.member,
      nickname,
      ...(look === undefined ? {} : { look }),
    },
  };
}

/** The member's push once they are let in: 「你已加入周三不练腿俱乐部，点击查看」. */
export function joinApprovedNotification(request: {
  readonly id: string;
  readonly squad: string;
  readonly squadName: string;
}): PushNotification {
  return {
    alert: pushAlert('push.joinApproved', [request.squadName]),
    category: 'joinApproved',
    thread: `join-${request.squad}`,
    collapseId: `join-${request.id}`,
    interruption: 'active',
    event: { kind: 'joinApproved', squadId: request.squad },
  };
}

/** Tells the squad's captain about a new request. Never fails the request: a failure is logged. */
export async function tellCaptain(
  deps: JoinRequestNewsDependencies,
  request: JoinRequest,
): Promise<void> {
  try {
    const captain = await deps.squads.captainOf(request.squad);
    if (captain === undefined) return;
    const asker = ProfileMember.parse(request.member);
    const character = (await deps.members.squadmates([asker])).get(asker)?.character;
    if (character === undefined || character === null) return;
    const notification = joinRequestNotification({
      request,
      nickname: character.nickname,
      look: {
        persona: character.look.persona,
        variants: { ...character.look.variants },
        colors: { ...character.look.colors },
      },
    });
    await tellAndPush(deps, {
      member: captain,
      notification,
      notice: {
        member: NoticeMember.parse(captain),
        squad: NoticeSquad.parse(request.squad),
        kind: 'joinRequest',
        subject: {
          version: 1,
          alert: noticeAlert(notification),
          request: request.id,
          member: NoticeMember.parse(request.member),
        },
      },
    });
  } catch (error) {
    deps.log.error('join request not told to the captain', { request: request.id, error });
  }
}

/** Tells the member they were let in. Never fails the answer: a failure is logged. */
export async function tellApproved(
  deps: JoinRequestNewsDependencies,
  request: JoinRequest,
): Promise<void> {
  try {
    const notification = joinApprovedNotification(request);
    await tellAndPush(deps, {
      member: request.member,
      notification,
      notice: {
        member: NoticeMember.parse(request.member),
        squad: NoticeSquad.parse(request.squad),
        kind: 'joinAnswered',
        subject: {
          version: 1,
          alert: noticeAlert(notification),
          request: request.id,
          approved: true,
        },
      },
    });
  } catch (error) {
    deps.log.error('join approval not told to the member', { request: request.id, error });
  }
}

/** Keeps the notice, then pushes unless the member turned off push or was told already. */
async function tellAndPush(
  deps: JoinRequestNewsDependencies,
  {
    member,
    notification,
    notice,
  }: {
    readonly member: string;
    readonly notification: PushNotification;
    readonly notice: NewNotice;
  },
) {
  const told = await deps.notices.tell([notice]);
  if (told.length === 0) return;
  const to = PushMember.parse(member);
  if (!(await deps.push.settingsOf(to)).dailyProgress) return;
  const outcome = await deps.push.notifyMembers({ members: [to], notification });
  if (outcome.failures.length > 0) {
    deps.log.warn('join push not sent to every phone', { member, failures: outcome.failures });
  }
}
