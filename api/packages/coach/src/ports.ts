import type { z } from 'zod';

import type { CoachCardKind, CoachOwnCard } from './domain/cards.js';
import type {
  Challenge,
  ChallengeAnswer,
  ChallengeCompletion,
  ChallengeDoneBy,
} from './domain/challenge.js';
import type { Coach, CoachId } from './domain/coach.js';
import type { StoredPath } from './domain/memory.js';
import type { CoachModel, CoachSettings, MemberId, SquadId } from './domain/settings.js';
import type { MemberFacts } from './domain/member-facts.js';
import type { CoachLetter, Handover } from './domain/letter.js';
import type { CoachAnswer, CoachEmoji, CoachReply } from './domain/reply.js';
import type { SquadWeek } from './domain/squad-week.js';
import type { NewWake, TokenUsage, Wake, WakeStep } from './domain/wake.js';

/** Where the coach settings are kept: one value, and a log of every change to it. */
export interface CoachSettingsStore {
  /**
   * The settings now. `forUpdate` holds the row until the caller's transaction ends, so two
   * admins changing them at once apply one change after the other.
   */
  current(options?: { readonly forUpdate?: boolean }): Promise<CoachSettings>;
  /**
   * Saves `settings` with `by` as who changed them, unless they are the settings already: then
   * nothing is saved or logged. Says whether anything changed.
   */
  save(settings: CoachSettings, by: MemberId): Promise<boolean>;
}

/** Where the coaches are kept, with a log of every change to each. */
export interface CoachCatalogStore {
  /** Every coach, retired ones too, by id. */
  list(): Promise<readonly Coach[]>;
  /**
   * Adds `coach`, or replaces the coach with its id, with `by` as who changed it, unless it is
   * that coach already: then nothing is saved or logged. Says whether anything changed.
   */
  save(coach: Coach, by: MemberId): Promise<boolean>;
}

/** A tool the coach may call during a wake: its arguments' shape, and what it answers. */
export interface CoachTool {
  readonly name: string;
  /** What the tool does, for the model, Chinese. */
  readonly description: string;
  /** Its arguments, which the model is held to. */
  readonly parameters: z.ZodObject;
  /** Runs it with the model's arguments, answering in words, or words and pictures, the model reads next. */
  run(input: unknown): Promise<ToolAnswer>;
}

/** What a tool answers: words, or words with pictures the model looks at, by their URLs. */
export type ToolAnswer = string | { readonly text: string; readonly images: readonly string[] };

/**
 * Short-lived URLs the model's provider can fetch a check-in's photos from, by their storage
 * paths, in the same order.
 */
export type CoachPhotoUrls = (paths: readonly string[]) => Promise<readonly string[]>;

/** What the coach can look up about these members: their counts, titles and this week's plan. */
export type CoachMemberFacts = (input: {
  readonly members: readonly string[];
  /** The Monday of the week whose plan to give. */
  readonly weekStart: string;
}) => Promise<readonly MemberFacts[]>;

/** A meme in use now, from the meme library: what it means and where it came from. */
export interface CoachMeme {
  readonly phrase: string;
  readonly meaning: string;
  readonly background: string;
}

/** The memes in use now, which the coach may draw humour from. */
export type CoachMemes = () => Promise<readonly CoachMeme[]>;

/**
 * Today's weather where each of these members is, in words (`今天雨，8–13°C，降水概率 80%；昨天晴，…`), for
 * those whose place is known. The model reads only the weather, never where they are.
 */
export type CoachWeather = (input: {
  readonly members: readonly string[];
  /** The day of the wake, `YYYY-MM-DD`. */
  readonly day: string;
}) => Promise<ReadonlyMap<string, string>>;

/** How a wake's run ended, with the tokens it used either way. */
export type AgentRun =
  | { readonly ok: true; readonly usage: TokenUsage }
  | { readonly ok: false; readonly usage: TokenUsage; readonly error: string };

/**
 * The agent a coach runs as: it reads the task, calls the tools as it decides, and stops when it
 * is done. Never throws; a run that fails says so, with the tokens it used.
 */
export interface CoachAgent {
  run(request: {
    readonly model: CoachModel;
    readonly instructions: string;
    readonly task: string;
    readonly tools: readonly CoachTool[];
    /**
     * Names the requests that begin the same way (one coach's instructions and tools), so the
     * provider keeps that beginning cached for them.
     */
    readonly cacheKey: string;
  }): Promise<AgentRun>;
}

/** The coach's queue of wakes. */
export interface CoachWakeStore {
  /** Adds the wakes not queued already, as queued at `now`; says how many were new. */
  enqueue(wakes: readonly NewWake[], now: Date): Promise<number>;
  /**
   * Claims the next wake of up to `limit` of these squads, at most one a squad and never a squad
   * whose wake is running: a wake a run claimed long enough ago that it must have stopped, or
   * else the oldest waiting one from the last day (one that failed waits a few minutes before
   * its next try). Each claim counts as a try.
   */
  claim(input: {
    readonly squads: readonly SquadId[];
    readonly limit: number;
    readonly now: Date;
  }): Promise<readonly Wake[]>;
  /** Marks a wake done. */
  finish(wake: number): Promise<void>;
  /** Puts a wake back to try again, or marks it failed after its last try, with why. */
  fail(wake: number, error: string): Promise<void>;
  /** Marks a wake skipped without running it (its coach was off duty), with why. */
  skip(wake: number, why: string): Promise<void>;
}

/** Each squad's memory files, every version kept. */
export interface CoachMemoryStore {
  /** The squad's files now, by stored path. */
  files(squad: SquadId): Promise<ReadonlyMap<StoredPath, string>>;
  /** Saves new versions of the squad's files, as one wake's changes, or an admin's. */
  save(input: {
    readonly squad: SquadId;
    /** The wake that changed them; left out for an admin's edit. */
    readonly wake?: number;
    readonly files: readonly { readonly path: StoredPath; readonly body: string }[];
  }): Promise<void>;
}

/** The coach's 战术板 lines. */
export interface CoachNoteStore {
  /** Saves the squad's line for a day unless it has one; says whether this one was saved. */
  save(note: {
    readonly squad: SquadId;
    readonly coach: CoachId;
    readonly day: string;
    readonly text: string;
    readonly wake: number;
  }): Promise<boolean>;
  /**
   * The last lines this coach wrote for the squad, newest first: never another coach's, so a new
   * coach doesn't take the last one's voice for its own.
   */
  recent(input: {
    readonly squad: SquadId;
    readonly coach: CoachId;
    readonly limit: number;
  }): Promise<readonly { readonly day: string; readonly text: string }[]>;
}

/** A coach's morning note (便条) to one member, as written. */
export interface MemberNote {
  readonly id: number;
  readonly squad: SquadId;
  readonly member: string;
  readonly coach: CoachId;
  /** The squad's day it was written for, `YYYY-MM-DD` (New York). */
  readonly day: string;
  readonly text: string;
  /** The day's challenge (今日挑战) the note sets, if any. */
  readonly challenge?: Challenge;
  readonly at: Date;
}

/** The coach's morning notes to each member: one a member a squad a day. */
export interface CoachMemberNoteStore {
  /** Saves the member's note for the day unless they have one; says whether this one was saved. */
  save(note: {
    readonly squad: SquadId;
    readonly member: string;
    readonly coach: CoachId;
    readonly day: string;
    readonly text: string;
    readonly challenge?: Challenge;
    readonly wake: number;
  }): Promise<boolean>;
  /**
   * The challenge the member's note of `day` (the squad's day) set, and what they said to it;
   * `undefined` when that note set none, there is no note, or it hasn't reached them yet.
   */
  challengeOf(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly day: string;
  }): Promise<DayChallenge | undefined>;
  /**
   * Marks the challenge on a note done, by the coach from the day's check-ins; false when it
   * set none, isn't for `day` (the squad's), was let go or was done already (the first stands).
   */
  complete(input: {
    readonly note: number;
    readonly by: ChallengeDoneBy;
    readonly day: string;
  }): Promise<boolean>;
  /** The challenges on the squad's notes of `day` that reached their members, by member. */
  challengesOn(input: {
    readonly squad: SquadId;
    readonly day: string;
  }): Promise<readonly (DayChallenge & { readonly member: string })[]>;
}

/** What a member said to a challenge, and why they let it go if they said. */
export interface ChallengeAnswered {
  readonly answer: ChallengeAnswer;
  readonly reason?: string;
}

/** A member's challenge on one day's note, as they and their coach read it. */
export interface DayChallenge {
  /** The note that set it. */
  readonly note: number;
  /** The squad's day it is for, `YYYY-MM-DD`. */
  readonly day: string;
  readonly challenge: Challenge;
  readonly answer: ChallengeAnswer | undefined;
  /** Why they let it go, if they said. */
  readonly reason: string | undefined;
  readonly completion: ChallengeCompletion | undefined;
}

/** What coaches said to check-ins: a line, an emoji or both, one a squad a check-in. */
export interface CoachReplyStore {
  /** Saves the reply unless the check-in has one in the squad; says whether this one was saved. */
  save(reply: {
    readonly squad: SquadId;
    readonly checkIn: string;
    readonly coach: CoachId;
    readonly text: string | undefined;
    readonly emoji: CoachEmoji | undefined;
    /** Whom its line @s, in the order written. */
    readonly mentions?: readonly string[];
    readonly wake: number;
  }): Promise<boolean>;
  /** What the squad's coach said to a check-in, if it said anything: its coach and line. */
  find(
    squad: SquadId,
    checkIn: string,
  ): Promise<{ readonly coach: CoachId; readonly text: string | undefined } | undefined>;
  /** The emoji this coach reacted with lately in the squad, newest first: never another coach's. */
  recent(input: {
    readonly squad: SquadId;
    readonly coach: CoachId;
    readonly limit: number;
  }): Promise<readonly CoachEmoji[]>;
}

/** What coaches answered members' replies to them, one a squad a reply. */
export interface CoachAnswerStore {
  /**
   * Saves the answer unless the reply has one in the squad, or is gone; says whether this one
   * was saved.
   */
  save(answer: {
    readonly squad: SquadId;
    readonly checkIn: string;
    readonly comment: string;
    readonly coach: CoachId;
    readonly text: string;
    /** Whom it @s, in the order written. */
    readonly mentions?: readonly string[];
    readonly wake: number;
  }): Promise<boolean>;
  /** The squad's answers under a check-in, oldest first. */
  ofCheckIn(
    squad: SquadId,
    checkIn: string,
  ): Promise<readonly { readonly comment: string; readonly text: string; readonly at: Date }[]>;
}

/** A 战术板 line as members read it, with the coach who wrote it. */
export interface CoachNoteShown {
  readonly day: string;
  readonly text: string;
  readonly coach: CoachReply['coach'];
  readonly at: Date;
}

/** A morning note as its member reads it, with the coach who wrote it. */
export interface CoachMemberNoteShown {
  readonly id: number;
  readonly day: string;
  readonly text: string;
  /** The day's challenge it sets, if any, and what the member said to it. */
  readonly challenge?: Challenge;
  readonly challengeAnswer?: ChallengeAnswer;
  readonly coach: CoachReply['coach'];
  readonly at: Date;
}

/** The morning notes to deliver: pushed and told in the bell, at 8am on each member's clock. */
export interface CoachNoteDeliveryStore {
  /** Notes written since `since` and not delivered yet, oldest first, with the coach's name. */
  undelivered(since: Date): Promise<readonly (MemberNote & { readonly coachName: string })[]>;
  /** Marks a note delivered; says whether this call did (a second one finds it done). */
  delivered(note: number): Promise<boolean>;
}

/** What a squad's coaches have said, as its members read it. */
export interface CoachActivityStore {
  /** The squad's newest 战术板 line, if it has one. */
  latestNote(squad: SquadId): Promise<CoachNoteShown | undefined>;
  /**
   * The member's newest morning note in the squad delivered since `since` that they haven't put
   * away yet, if any.
   */
  memberNote(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly since: Date;
  }): Promise<CoachMemberNoteShown | undefined>;
  /** The letter the squad's coach now was left when it took over (换教练), if it was left one. */
  letter(squad: SquadId): Promise<CoachLetter | undefined>;
  /**
   * The member's answer to their note's challenge (接受挑战 or 算了); `noNote` when the note
   * isn't theirs in the squad or hasn't reached them yet, `noChallenge` when it set none. The
   * first answer stands.
   */
  answerChallenge(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly note: number;
    readonly answer: ChallengeAnswer;
    /** Why they let it go, with `declined` only. */
    readonly reason?: string;
  }): Promise<ChallengeAnswered | 'noNote' | 'noChallenge'>;
  /**
   * The member's challenge on their note of `day` (the squad's day), once delivered; the same
   * as the coach's `challengeOf`.
   */
  challengeOf(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly day: string;
  }): Promise<DayChallenge | undefined>;
  /**
   * The member marks their note's challenge done (我完成了) on `today`, the squad's day:
   * `noNote` when the note isn't theirs in the squad or hasn't reached them, `noChallenge` when
   * it set none, `declined` when they let it go, `dayOver` when it was another day's. The first
   * one stands, the coach's too, and is what comes back.
   */
  completeChallenge(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly note: number;
    readonly today: string;
  }): Promise<ChallengeCompletion | 'noNote' | 'noChallenge' | 'declined' | 'dayOver'>;
  /** The member put their note away (收下); false when it isn't theirs in the squad. Once. */
  putAway(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly note: number;
  }): Promise<boolean>;
  /**
   * The coach's own cards for the member in the squad since `since`, oldest first: its 战术板
   * lines, the member's delivered notes and their challenges, its lines to the member's
   * check-ins and its answers to the member's replies.
   */
  cards(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly since: Date;
  }): Promise<readonly CoachOwnCard[]>;
  /** The keys (`cardKey`) of the cards the member has seen in the squad. */
  seenCards(input: { readonly squad: SquadId; readonly member: string }): Promise<Set<string>>;
  /** Marks a card seen for the member; once, however many times it is called. */
  markSeen(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly kind: CoachCardKind;
    readonly id: string;
  }): Promise<void>;
  /** The squad's replies to these check-ins, in no order; a check-in with none is left out. */
  replies(squad: SquadId, checkIns: readonly string[]): Promise<readonly CoachReply[]>;
  /** The squad's answers to replies under these check-ins, oldest first. */
  answers(squad: SquadId, checkIns: readonly string[]): Promise<readonly CoachAnswer[]>;
}

/**
 * The tokens each wake used, per squad, for usage-based billing later. Recorded even when the
 * wake has gone meanwhile (its check-in was deleted): then without it.
 */
export interface CoachUsageStore {
  record(entry: {
    readonly squad: SquadId;
    /** The wake that used them; none for a letter, which runs outside the queue. */
    readonly wake?: number;
    readonly coach: CoachId;
    readonly model: CoachModel;
    readonly usage: TokenUsage;
    readonly costMicros: number;
    readonly at: Date;
  }): Promise<void>;
  /** What was spent since `since`, in US dollars' millionths: by this squad, or by every squad. */
  spent(input: { readonly squad?: SquadId; readonly since: Date }): Promise<number>;
}

/** Each wake's tool calls, in order, for the admins to see how the coach worked. */
export interface CoachStepStore {
  /** Records a run's steps; recorded even when the wake has gone meanwhile: then nothing. */
  record(input: {
    readonly squad: SquadId;
    readonly wake: number;
    readonly steps: readonly WakeStep[];
  }): Promise<void>;
}

/** The stores a wake's outcome is saved to, together. */
export interface CoachStores {
  readonly wakes: CoachWakeStore;
  readonly memory: CoachMemoryStore;
  readonly notes: CoachNoteStore;
  readonly memberNotes: CoachMemberNoteStore;
  readonly replies: CoachReplyStore;
  readonly answers: CoachAnswerStore;
  readonly usage: CoachUsageStore;
  readonly steps: CoachStepStore;
}

/** Runs `work` on the stores in one transaction: all of it is saved, or none. */
export type CoachTransaction = <T>(work: (stores: CoachStores) => Promise<T>) => Promise<T>;

/** A squad's week as the coach sees it, from the check-ins and members modules. */
export type SquadWeekSource = (input: {
  readonly squad: SquadId;
  readonly weekStart: string;
}) => Promise<SquadWeek>;

/**
 * Those of these members who agreed to having their words sent to AI providers (the current
 * copy): only their words reach the model.
 */
export type AiConsented = (members: readonly string[]) => Promise<readonly string[]>;

/**
 * The app's own moments on `day` (`YYYY-MM-DD`, New York), such as a limited store open
 * (「TURKEY TROT 限时开张」), kept as data with the switches, never in code; holidays come from
 * the coach's own calendar in its settings.
 */
export type CoachOccasions = (day: string) => Promise<readonly string[]>;

/** The coach each squad has hired, and every hire and firing. */
export interface CoachHiringStore {
  /** The coach the squad has hired now and since when, if any. */
  coachOf(squad: SquadId): Promise<{ readonly coach: CoachId; readonly since: Date } | undefined>;
  /** Every squad with a coach hired now, with its coach. */
  hired(): Promise<ReadonlyMap<SquadId, CoachId>>;
  /**
   * Whether the squad's coach was its coach before, was fired and is back, and has not run for it
   * since it came back (a wake skipped without running, as for a check-in no longer shared with
   * AI, doesn't count), from the hires and firings log and the usage log.
   */
  backAgain(squad: SquadId): Promise<boolean>;
  /**
   * Hires `coach` for the squad, logged as `by`'s, unless it has a coach: then nothing is
   * saved. `noSquad` when there is no such squad.
   */
  hire(input: {
    readonly squad: SquadId;
    readonly coach: CoachId;
    readonly by: MemberId;
  }): Promise<'hired' | 'hasCoach' | 'noSquad'>;
  /** Fires the squad's coach, logged as `by`'s; the coach fired, or `undefined` for none. */
  fire(input: { readonly squad: SquadId; readonly by: MemberId }): Promise<CoachId | undefined>;
  /**
   * Hires `coach` for the squad in one transaction, firing the coach it has first (both logged
   * as `by`'s): `same` when it is that coach already, and nothing is saved; `noSquad` when
   * there is no such squad.
   */
  replace(input: {
    readonly squad: SquadId;
    readonly coach: CoachId;
    readonly by: MemberId;
  }): Promise<'hired' | 'same' | 'noSquad'>;
}

/** The letters coaches leave the next one when their squad changes coach (换教练). */
export interface CoachLetterStore {
  /**
   * The squad's change of coach that brought its coach now, when it came by one (fired the coach
   * before it and hired it in one step); `undefined` for a coach hired with none before it.
   */
  handover(squad: SquadId): Promise<Handover | undefined>;
  /** The squad's hires and firings, oldest first. */
  history(squad: SquadId): Promise<
    readonly {
      readonly kind: 'hired' | 'fired';
      readonly coach: CoachId;
      readonly at: Date;
    }[]
  >;
  /** Claims the one try at a change's letter; false when it was tried already. */
  claim(handover: Handover): Promise<boolean>;
  /** Saves the letter for a change it claimed. */
  save(letter: {
    readonly handover: Handover;
    readonly day: string;
    readonly text: string;
  }): Promise<void>;
  /** The letter written for a change, by its hire, if one was. */
  ofHandover(hireEvent: number): Promise<CoachLetter | undefined>;
}

/** What a squad's coach has done, for the admins: its files, lines, wakes and tokens. */
export interface SquadCoaching {
  readonly version: 1;
  /** The coach it has hired now, or null. */
  readonly coach: CoachId | null;
  /** Each file now, by stored path (`people/<member id>.md`), with when it last changed. */
  readonly files: readonly { readonly path: string; readonly body: string; readonly at: Date }[];
  /** The last 战术板 lines, newest first. */
  readonly notes: readonly { readonly day: string; readonly text: string }[];
  /** The last wakes, newest first, with why a failed one failed. */
  readonly wakes: readonly {
    readonly reason: 'checkIn' | 'comment' | 'daily' | 'dream';
    readonly state: string;
    readonly tries: number;
    readonly lastError: string | null;
    readonly createdAt: Date;
    /** Its runs' tool calls, in order. */
    readonly steps: readonly WakeStep[];
  }[];
  /** Every wake's tokens and cost so far, and those of the last 7 days. */
  readonly usage: Readonly<Record<'total' | 'lastWeek', UsageTotal>>;
}

export interface UsageTotal {
  readonly wakes: number;
  readonly requests: number;
  readonly inputTokens: number;
  /** Those of the input tokens the provider had cached. */
  readonly cachedInputTokens: number;
  readonly outputTokens: number;
  /** US dollars in millionths. */
  readonly costMicros: number;
}

/** Reads what a squad's coach has done. */
export interface CoachReportStore {
  squad(squad: SquadId, now: Date): Promise<SquadCoaching>;
}

/**
 * Coaches' gifts, kept by the unlocks module: the pool a coach may give from, who in a squad may
 * get one now (one a member a week at most, on the squad's clock; Tracy, 2026-11-08), and giving.
 */
export interface CoachGifting {
  /**
   * The pieces offered now with what each is, and of these members those who may get a gift
   * this week, each with the gift pieces they already have.
   */
  options(input: { readonly squad: SquadId; readonly members: readonly string[] }): Promise<{
    readonly pool: readonly { readonly id: string; readonly description?: string }[];
    readonly open: ReadonlyMap<string, readonly string[]>;
  }>;
  /** Gives the piece with the coach's line; why not, when it was refused. */
  give(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly coach: CoachId;
    readonly piece: string;
    readonly line: string;
  }): Promise<string | undefined>;
}
