import type { CoachNoteDelivery, NoteToDeliver } from '@wildcard/coach';
import type { Members } from '@wildcard/members';
import {
  MemberId as NoticeMember,
  SquadId as NoticeSquad,
  type NewNotice,
} from '@wildcard/notices';
import { MemberId as PushMember, type Push, type PushNotification } from '@wildcard/push';
import { SquadId, type Squads } from '@wildcard/squads';

import type { Log } from '../log.js';
import { pushAlert } from '../push-copy.js';

export interface CoachNotesDependencies {
  readonly notes: CoachNoteDelivery;
  /** The hour on each member's clock when their note reaches them, from the coach settings. */
  readonly noteHour: () => Promise<number>;
  readonly members: Pick<Members, 'pastLocalHour'>;
  /** Who is in each squad now: a member who left gets no note from it. */
  readonly squads: Pick<Squads, 'membersOf'>;
  readonly push: Pick<Push, 'settingsOf' | 'notifyMembers'>;
  /** Keeps notices in the members' bells; never throws. */
  readonly tell: (told: readonly NewNotice[]) => Promise<void>;
  readonly log: Log;
  readonly clock: () => Date;
}

export interface CoachNotesRun {
  /** Notes written lately and not delivered yet. */
  readonly waiting: number;
  /** Of those, the ones whose member's clock reached the hour, now delivered. */
  readonly delivered: number;
  /** Of those, the ones pushed to at least one phone. */
  readonly pushed: number;
}

/**
 * Delivers the coach's morning notes (便条) once each member's clock passes the settings' hour:
 * a notice in their bell whatever their switches, and a silent push under their `coach` switch.
 * A note written after that hour (a member east of New York) goes at once. Each note is claimed
 * before it is told, so runs that overlap tell it once. Never throws.
 */
export async function deliverCoachNotes(deps: CoachNotesDependencies): Promise<CoachNotesRun> {
  try {
    const now = deps.clock();
    const waiting = await deps.notes.waiting(now);
    if (waiting.length === 0) return { waiting: 0, delivered: 0, pushed: 0 };
    const morning = new Set<string>(
      (await deps.members.pastLocalHour({ hour: await deps.noteHour(), now })).map(
        ({ member }) => member,
      ),
    );
    const inSquad = new Map<string, ReadonlySet<string>>();
    const stillIn = async (note: NoteToDeliver) => {
      let members = inSquad.get(note.squad);
      if (members === undefined) {
        members = new Set<string>(await deps.squads.membersOf(SquadId.parse(note.squad)));
        inSquad.set(note.squad, members);
      }
      return members.has(note.member);
    };
    let delivered = 0;
    let pushed = 0;
    for (const note of waiting) {
      if (!morning.has(note.member) || !(await stillIn(note))) continue;
      if (!(await deps.notes.delivered(note.id))) continue;
      delivered += 1;
      await deps.tell([
        {
          member: NoticeMember.parse(note.member),
          squad: NoticeSquad.parse(note.squad),
          kind: 'coachNote',
          subject: { version: 1, note: note.id, coach: note.coach, day: note.day, text: note.text },
        },
      ]);
      if (await pushNote(deps, note)) pushed += 1;
    }
    return { waiting: waiting.length, delivered, pushed };
  } catch (error) {
    deps.log.warn('coach notes not delivered', { error });
    return { waiting: 0, delivered: 0, pushed: 0 };
  }
}

/**
 * The push of a morning note: 「毛头给你留了张便条：…」, silent, as every coach push is. A tap opens
 * 今天, where the note waits.
 */
export function coachNoteNotification(note: {
  readonly id: number;
  readonly coachName: string;
  readonly text: string;
}): PushNotification {
  return {
    alert: pushAlert('push.coach.note', [note.coachName, note.text]),
    category: 'coachNote',
    thread: 'coach-notes',
    collapseId: `coach-note-${String(note.id)}`,
    interruption: 'passive',
    event: { kind: 'coachNote', note: note.id },
  };
}

async function pushNote(
  deps: Pick<CoachNotesDependencies, 'push' | 'log'>,
  note: NoteToDeliver,
): Promise<boolean> {
  try {
    const to = PushMember.parse(note.member);
    // The coach's own switch; the note is in the member's bell and on 今天 whatever it is.
    if (!(await deps.push.settingsOf(to)).coach) return false;
    const outcome = await deps.push.notifyMembers({
      members: [to],
      notification: coachNoteNotification(note),
    });
    if (outcome.failures.length > 0) {
      deps.log.warn('coach note not pushed to every phone', {
        member: note.member,
        failures: outcome.failures,
      });
    }
    return outcome.sent > 0;
  } catch (error) {
    deps.log.warn('coach note push failed', { member: note.member, error });
    return false;
  }
}
