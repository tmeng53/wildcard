import type { z } from 'zod';

import type { Coach, CoachId } from './domain/coach.js';
import type { StoredPath } from './domain/memory.js';
import type { CoachModel, CoachSettings, MemberId, SquadId } from './domain/settings.js';
import type { SquadWeek } from './domain/squad-week.js';
import type { NewWake, TokenUsage, Wake } from './domain/wake.js';

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
  /** Runs it with the model's arguments, answering in words the model reads next. */
  run(input: unknown): Promise<string>;
}

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

/** The stores a wake's outcome is saved to, together. */
export interface CoachStores {
  readonly wakes: CoachWakeStore;
  readonly memory: CoachMemoryStore;
  readonly notes: CoachNoteStore;
  readonly usage: CoachUsageStore;
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
    readonly reason: 'checkIn' | 'daily';
    readonly state: string;
    readonly tries: number;
    readonly lastError: string | null;
    readonly createdAt: Date;
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
