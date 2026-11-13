import {
  CheckInId,
  MemberId as CheckInMember,
  SquadId,
  type CheckIns,
  type Training,
} from '@wildcard/check-ins';
import type { ReaderLanguage } from '@wildcard/language-model';
import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import {
  MemberId as PushMember,
  apnsPayload,
  type Push,
  type PushNotification,
  type TeammatePushRing,
} from '@wildcard/push';
import type { LocalizedNames } from '@wildcard/sports';

import type { Log } from '../log.js';
import { pushAlert } from '../push-copy.js';
import { APNS_BYTES } from './daily-progress-push.js';
import { pushToday, type PushToday } from './daily-push-today.js';

export interface TeammatePushDependencies {
  readonly checkIns: Pick<CheckIns, 'current' | 'squadToday' | 'listForSquad'>;
  readonly members: Pick<Members, 'squadmates' | 'languages'>;
  /** Every listed sport's names, by its id. */
  readonly sportNames: () => Promise<ReadonlyMap<string, LocalizedNames>>;
  readonly push: Pick<Push, 'teammateSettings' | 'claimTeammate' | 'settingsOf' | 'notifyMembers'>;
  readonly clock: () => Date;
  readonly log: Log;
}

/**
 * The generation of pushes that has the teammate push's words (`PushGeneration`): a phone on an
 * older build is skipped.
 */
export const TEAMMATE_PUSH_SINCE = 2;

const NAMES_KEY = {
  'zh-Hans': 'zhHans',
  'zh-Hant': 'zhHant',
  en: 'en',
} as const satisfies Record<ReaderLanguage, keyof LocalizedNames>;

/**
 * Tells a member's squadmates of the 训练 they just posted (「小美刚练完网球 62 分钟」), each on
 * their phone at once: the trigger the squad runs on, since a teammate training is what gets the
 * next one out. Only a 训练 posted to the squad's 动态 for the day it was posted on (a 补打卡 for an
 * earlier day is no news), never to its author, and only to those who left 通知 on (the
 * `dailyProgress` switch). The first few a member gets in 24 hours ring (the settings'
 * `dailyRings`); the rest arrive silently, so a busy squad never becomes noise. Its long-press
 * view is the 6pm push's: the squad's week and today's posts, to cheer in place. It isn't kept
 * in 通知: the post is in 动态.
 *
 * Runs as the `teammate-push` subscriber of `check-in.created`. Each member's push is claimed
 * before it is sent, so an event delivered twice pushes once; reading the post failing throws,
 * so the event comes again.
 */
export async function notifyTeammates(
  deps: TeammatePushDependencies,
  { checkIn, squads }: { readonly checkIn: string; readonly squads: readonly string[] },
): Promise<void> {
  const settings = await deps.push.teammateSettings();
  if (!settings.sending) return;
  const record = await deps.checkIns.current(CheckInId.parse(checkIn));
  if (record?.kind !== 'trained' || !record.inFeed) return;
  if (record.postedDay !== undefined && record.postedDay !== record.day) return;
  const author = record.member;
  const nickname = (await deps.members.squadmates([ProfileMember.parse(author)])).get(
    ProfileMember.parse(author),
  )?.character?.nickname;
  // A member without a name yet is still mid-sign-up, and can't have posted; say nothing.
  if (nickname === undefined) return;

  // Each teammate once, through the first squad they share with the author.
  const through = new Map<string, SquadId>();
  for (const each of squads) {
    const squad = SquadId.parse(each);
    if (!record.audience.includes(squad)) continue;
    const { members } = await deps.checkIns.squadToday({ viewer: author, squad });
    for (const { member } of members) {
      if (member !== author && !through.has(member)) through.set(member, squad);
    }
  }
  if (through.size === 0) return;
  const [languages, sportNames] = await Promise.all([
    deps.members.languages([...through.keys()].map((each) => ProfileMember.parse(each))),
    deps.sportNames(),
  ]);
  const sportIn = (language: ReaderLanguage) =>
    record.training.customSport ??
    sportNames.get(record.training.sport)?.[NAMES_KEY[language]] ??
    record.training.sport;

  await Promise.all(
    [...through].map(async ([member, squad]) => {
      try {
        const to = PushMember.parse(member);
        if (!(await deps.push.settingsOf(to)).dailyProgress) return;
        const ring = await deps.push.claimTeammate({
          checkIn,
          member: to,
          at: deps.clock(),
          dailyRings: settings.dailyRings,
        });
        if (ring === undefined) return;
        const told = {
          checkIn,
          squad,
          nickname,
          sport: sportIn(languages.get(ProfileMember.parse(member)) ?? 'zh-Hans'),
          minutes: record.training.minutes,
          ring,
        };
        const notification = await withToday(deps, { member, squad, told });
        const outcome = await deps.push.notifyMembers({ members: [to], notification });
        if (outcome.failures.length > 0) {
          deps.log.warn('teammate push not sent to every phone', {
            member,
            failures: outcome.failures,
          });
        }
      } catch (error) {
        // One teammate's failure never stops the others'; a claimed push isn't tried again.
        deps.log.error('teammate push not sent', { checkIn, member, error });
      }
    }),
  );
}

type Told = Omit<Parameters<typeof teammateNotification>[0], 'squadWeek' | 'today'>;

/** The push with the member's squad's week and today's posts, for its long-press view. */
async function withToday(
  deps: TeammatePushDependencies,
  {
    member,
    squad,
    told,
  }: { readonly member: string; readonly squad: SquadId; readonly told: Told },
): Promise<PushNotification> {
  const today = await deps.checkIns.squadToday({ viewer: CheckInMember.parse(member), squad });
  const rest = { ...told, squadWeek: today.squadWeek };
  const bytes =
    APNS_BYTES -
    Buffer.byteLength(JSON.stringify(apnsPayload(teammateNotification(rest)))) -
    Buffer.byteLength(',"today":');
  return teammateNotification({
    ...rest,
    today: await pushToday(deps, { viewer: member, squad, today, pokers: [], bytes }).catch(
      (error: unknown) => {
        // The long-press view is extra: the push still goes, and the phone shows its words alone.
        deps.log.warn('teammate push sent without today', { member, error });
        return undefined;
      },
    ),
  });
}

/**
 * The teammate push, without its words: a String Catalog key filled with who trained, the sport
 * in the reader's language and, when the post has them, the minutes: 「小美刚练完网球 62 分钟」 or
 * 「小美刚练完网球」. A tap opens the post's page. `event` is the daily push's (the squad's week
 * and today's posts) with the check-in, so the same long-press view shows it.
 */
export function teammateNotification({
  checkIn,
  squad,
  nickname,
  sport,
  minutes,
  ring,
  squadWeek,
  today,
}: {
  readonly checkIn: string;
  readonly squad: string;
  /** Who trained. */
  readonly nickname: string;
  /** The sport's name as the reader's app says it, or the member's own words for one. */
  readonly sport: string;
  readonly minutes?: Training['minutes'];
  readonly ring: TeammatePushRing;
  readonly squadWeek: { readonly trainedDays: number; readonly plannedDays: number };
  /** Teammates' check-ins today, for the long-press view; left out when they couldn't be read. */
  readonly today?: PushToday | undefined;
}): PushNotification {
  return {
    alert:
      minutes === undefined
        ? pushAlert('push.teammate.trained', [nickname, sport])
        : pushAlert('push.teammate.trained.minutes', [nickname, sport, String(minutes)]),
    category: 'teammateCheckIn',
    thread: 'teammates',
    collapseId: `teammate-${checkIn}`,
    interruption: ring === 'ring' ? 'active' : 'passive',
    since: TEAMMATE_PUSH_SINCE,
    event: {
      kind: 'teammateCheckIn',
      checkIn,
      squad,
      squadTrainedDays: squadWeek.trainedDays,
      squadPlannedDays: squadWeek.plannedDays,
      ...(today === undefined ? {} : { today }),
    },
  };
}
