import type { CoachAnswer, CoachReply } from '../domain/reply.js';
import type { SquadId } from '../domain/settings.js';
import type { CoachActivityStore, CoachNoteShown } from '../ports.js';

/** The most check-ins one read asks about: a page of 动态. */
export const MAX_CHECK_INS = 100;

/** What a squad's coaches have said, as its members read it. */
export interface SquadCoachActivity {
  /** The newest 战术板 line, if the squad has one. */
  readonly note: CoachNoteShown | undefined;
  /** The replies to the check-ins asked about; one with none is left out. */
  readonly replies: readonly CoachReply[];
  /** Its answers to members' replies under those check-ins, oldest first. */
  readonly answers: readonly CoachAnswer[];
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
  }): Promise<SquadCoachActivity>;
  /**
   * Whether `coach` wrote a line to the check-in for any of these squads, so a member who sees
   * it through them may reply to it.
   */
  spoke(input: {
    readonly squads: readonly SquadId[];
    readonly checkIn: string;
    readonly coach: string;
  }): Promise<boolean>;
}

export function createCoachActivity(deps: { readonly store: CoachActivityStore }): CoachActivity {
  return {
    squad: async ({ squad, checkIns }) => {
      const asked = [...new Set(checkIns.map((id) => id.toLowerCase()))].slice(0, MAX_CHECK_INS);
      const [note, replies, answers] = await Promise.all([
        deps.store.latestNote(squad),
        deps.store.replies(squad, asked),
        deps.store.answers(squad, asked),
      ]);
      return { note, replies, answers };
    },
    spoke: async ({ squads, checkIn, coach }) => {
      const replies = await Promise.all(
        squads.map((squad) => deps.store.replies(squad, [checkIn.toLowerCase()])),
      );
      return replies.flat().some((reply) => reply.coach.id === coach && reply.text !== undefined);
    },
  };
}
