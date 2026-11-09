import { isCardId, type CoachCardKind, type CoachOwnCard } from '../domain/cards.js';
import type { CoachLetter } from '../domain/letter.js';
import type { CoachAnswer, CoachReply } from '../domain/reply.js';
import type { SquadId } from '../domain/settings.js';
import type { ChallengeAnswer, ChallengeCompletion } from '../domain/challenge.js';
import {
  CoachCardIdError,
  CoachChallengeDayOverError,
  CoachChallengeDeclinedError,
  CoachNoteNoChallengeError,
  CoachNoteNotFoundError,
} from '../errors.js';
import type {
  ChallengeAnswered,
  CoachActivityStore,
  CoachMemberNoteShown,
  CoachNoteShown,
  DayChallenge,
} from '../ports.js';

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
  /** The letter the squad's coach now was left when it took over (换教练), if it was left one. */
  readonly letter: CoachLetter | undefined;
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
  /**
   * The reader's answer to their morning note's challenge (接受挑战 or 算了, with why if they
   * say), answered with the one that stands: the first. Throws `CoachNoteNotFoundError` when the note isn't theirs in
   * this squad, `CoachNoteNoChallengeError` when it sets none.
   */
  answerChallenge(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly note: number;
    readonly answer: ChallengeAnswer;
    /** Why they let it go, with `declined` only; the caller checks that. */
    readonly reason?: string;
  }): Promise<ChallengeAnswered>;
  /**
   * The reader's challenge today (`today`, the squad's day), once their note reached them: what
   * it is, what they said to it and whether it is done. The caller checks they are in the squad.
   */
  challenge(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly today: string;
  }): Promise<DayChallenge | undefined>;
  /**
   * The reader did their note's challenge (我完成了), on its own day (`today`, the squad's):
   * answered with the completion that stands, the first, theirs or the coach's. Throws
   * `CoachNoteNotFoundError` when the note isn't theirs in this squad, `CoachNoteNoChallengeError`
   * when it sets none, `CoachChallengeDeclinedError` when they let it go and
   * `CoachChallengeDayOverError` when it was another day's.
   */
  completeChallenge(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly note: number;
    readonly today: string;
  }): Promise<ChallengeCompletion>;
  /**
   * The coach's own cards for the member in the squad since `since`, oldest first, and the keys
   * (`cardKey`) of every card they have seen there, the gifts' too. The caller checks they are in
   * the squad.
   */
  cards(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly since: Date;
  }): Promise<{ readonly cards: readonly CoachOwnCard[]; readonly seen: ReadonlySet<string> }>;
  /**
   * The member swiped a card away: seen, once. Seeing a note also puts it away on 今天 (收下).
   * The caller checks they are in the squad; an id that isn't theirs marks nothing they can see.
   * Throws `CoachCardIdError` for an id not shaped like one of `kind` (`isCardId`).
   */
  markSeen(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly kind: CoachCardKind;
    readonly id: string;
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
      const [note, replies, answers, memberNote, letter] = await Promise.all([
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
        deps.store.letter(squad),
      ]);
      return { note, replies, answers, memberNote, letter };
    },
    putAway: async (input) => {
      if (!(await deps.store.putAway(input))) throw new CoachNoteNotFoundError();
    },
    answerChallenge: async (input) => {
      const kept = await deps.store.answerChallenge(input);
      if (kept === 'noNote') throw new CoachNoteNotFoundError();
      if (kept === 'noChallenge') throw new CoachNoteNoChallengeError();
      return kept;
    },
    challenge: ({ squad, member, today }) => deps.store.challengeOf({ squad, member, day: today }),
    completeChallenge: async (input) => {
      const done = await deps.store.completeChallenge(input);
      if (done === 'noNote') throw new CoachNoteNotFoundError();
      if (done === 'noChallenge') throw new CoachNoteNoChallengeError();
      if (done === 'declined') throw new CoachChallengeDeclinedError();
      if (done === 'dayOver') throw new CoachChallengeDayOverError();
      return done;
    },
    cards: async (input) => {
      const [cards, seen] = await Promise.all([
        deps.store.cards(input),
        deps.store.seenCards({ squad: input.squad, member: input.member }),
      ]);
      return { cards, seen };
    },
    markSeen: async (input) => {
      if (!isCardId(input.kind, input.id)) throw new CoachCardIdError();
      await deps.store.markSeen(input);
      if (input.kind === 'note') {
        await deps.store.putAway({
          squad: input.squad,
          member: input.member,
          note: Number(input.id),
        });
      }
    },
    // A line of the coach's under the post: its reply to the check-in, or an answer it gave
    // there to a member's reply or @ (a member may reply to either).
    spoke: async ({ squads, checkIn, coach }) => {
      const asked = [checkIn.toLowerCase()];
      const said = await Promise.all(
        squads.map(async (squad) => {
          const [replies, answers] = await Promise.all([
            deps.store.replies(squad, asked),
            deps.store.answers(squad, asked),
          ]);
          return (
            replies.some((reply) => reply.coach.id === coach && reply.text !== undefined) ||
            answers.some((answer) => answer.coach.id === coach)
          );
        }),
      );
      return said.includes(true);
    },
  };
}
