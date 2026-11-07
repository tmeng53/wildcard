import type { z } from 'zod';

import type { Coach, CoachId } from './domain/coach.js';
import type { StoredPath } from './domain/memory.js';
import type { CoachModel, CoachSettings, MemberId, SquadId } from './domain/settings.js';
import type { MemberFacts } from './domain/member-facts.js';
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
}

/** Each squad's memory files, every version kept. */
export interface CoachMemoryStore {
  /** The squad's files now, by stored path. */
  files(squad: SquadId): Promise<ReadonlyMap<StoredPath, string>>;
  /** Saves new versions of the squad's files, as one wake's changes. */
  save(input: {
    readonly squad: SquadId;
    readonly wake: number;
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
  /** The squad's last lines, newest first. */
  recent(
    squad: SquadId,
    limit: number,
  ): Promise<readonly { readonly day: string; readonly text: string }[]>;
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
    readonly wake: number;
  }): Promise<boolean>;
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
    readonly wake: number;
  }): Promise<boolean>;
  /** What the squad's coach said to a check-in, if it said anything: its coach and line. */
  find(
    squad: SquadId,
    checkIn: string,
  ): Promise<{ readonly coach: CoachId; readonly text: string | undefined } | undefined>;
  /** The emoji the squad's coaches reacted with lately, newest first. */
  recent(squad: SquadId, limit: number): Promise<readonly CoachEmoji[]>;
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
  /** The member put their note away (收下); false when it isn't theirs in the squad. Once. */
  putAway(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly note: number;
  }): Promise<boolean>;
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
    readonly wake: number;
    readonly coach: CoachId;
    readonly model: CoachModel;
    readonly usage: TokenUsage;
    readonly costMicros: number;
  }): Promise<void>;
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
    readonly reason: 'checkIn' | 'comment' | 'daily';
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
