import type { CoachAnswer, CoachReply } from '../domain/reply.js';
import type { SquadId } from '../domain/settings.js';
import { CoachNoteNotFoundError } from '../errors.js';
import type { CoachActivityStore, CoachMemberNoteShown, CoachNoteShown } from '../ports.js';

/** The most check-ins one read asks about: a page of 动态. */
export const MAX_CHECK_INS = 100;

/**
 * How long a morning note waits on 今天 after it reached the reader: the rest of that day (8am
 * to past midnight), so one they never opened the app for stays only in 通知.
 */
const NOTE_FRESH_MS = 18 * 60 * 60_000;

/** What a squad's coaches have said, as its members read it. */
export interface SquadCoachActivity {
  /** The newest 战术板 line, if the squad has one. */
  readonly note: CoachNoteShown | undefined;
  /** The replies to the check-ins asked about; one with none is left out. */
  readonly replies: readonly CoachReply[];
  /** Its answers to members' replies under those check-ins, oldest first. */
  readonly answers: readonly CoachAnswer[];
  /** The reader's own newest morning note from the squad's coach, while it is fresh and not put away. */
  readonly memberNote: CoachMemberNoteShown | undefined;
}

export interface CoachActivity {
  /**
   * What the squad's coaches said: its newest 战术板 line, their replies to these check-ins
   * (up to `MAX_CHECK_INS`, the rest ignored) and their answers to members' replies there. The caller checks the reader is in the squad. A
   * reply stays after its coach is fired, with that coach's name.
   */
  squad(input: {
    readonly squad: SquadId;
    readonly checkIns: readonly string[];
    /** Who reads it, for their own morning note. */
    readonly reader?: string;
    readonly now?: Date;
  }): Promise<SquadCoachActivity>;
  /**
   * Whether `coach` wrote a line to the check-in for any of these squads, so a member who sees
   * it through them may reply to it.
   */
  /**
   * The reader put their morning note away on 今天 (收下), so no phone shows it again. Safe to
   * repeat. Throws `CoachNoteNotFoundError` when it isn't theirs in this squad.
   */
  putAway(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly note: number;
  }): Promise<void>;
  spoke(input: {
    readonly squads: readonly SquadId[];
    readonly checkIn: string;
    readonly coach: string;
  }): Promise<boolean>;
}

export function createCoachActivity(deps: { readonly store: CoachActivityStore }): CoachActivity {
  return {
    squad: async ({ squad, checkIns, reader, now = new Date() }) => {
      const asked = [...new Set(checkIns.map((id) => id.toLowerCase()))].slice(0, MAX_CHECK_INS);
      const [note, replies, answers, memberNote] = await Promise.all([
        deps.store.latestNote(squad),
        deps.store.replies(squad, asked),
        deps.store.answers(squad, asked),
        reader === undefined
          ? Promise.resolve(undefined)
          : deps.store.memberNote({
              squad,
              member: reader,
              since: new Date(now.getTime() - NOTE_FRESH_MS),
            }),
      ]);
      return { note, replies, answers, memberNote };
    },
    putAway: async (input) => {
      if (!(await deps.store.putAway(input))) throw new CoachNoteNotFoundError();
    },
    spoke: async ({ squads, checkIn, coach }) => {
      const replies = await Promise.all(
        squads.map((squad) => deps.store.replies(squad, [checkIn.toLowerCase()])),
      );
      return replies.flat().some((reply) => reply.coach.id === coach && reply.text !== undefined);
    },
  };
}
