import type { Coach, CoachId } from '../domain/coach.js';
import {
  shownBody,
  shownPaths,
  storedBody,
  storedPathOf,
  type StoredPath,
} from '../domain/memory.js';
import { instructionsOf, taskOf, type CoachThread } from '../domain/prompt.js';
import type { CoachEmoji } from '../domain/reply.js';
import type { CoachSettings, SquadId } from '../domain/settings.js';
import { consentedOnly, rosterOf, type SquadWeek } from '../domain/squad-week.js';
import { costMicros, wakesDue, weekStartOf, weeksAround, type Wake } from '../domain/wake.js';
import type {
  AiConsented,
  CoachAgent,
  CoachCatalogStore,
  CoachHiringStore,
  CoachSettingsStore,
  CoachStores,
  CoachTransaction,
  SquadWeekSource,
} from '../ports.js';
import { toolbox, type WakeDraft } from './coach-wakes/toolbox.js';

/**
 * How long a run keeps claiming wakes, so it ends well inside the scheduler's 5 minutes; the
 * rest wait for the next run.
 */
const RUN_BUDGET_MS = 150_000;

/** How many squads' wakes run at once; each round claims one wake of each. */
const AT_ONCE = 4;

/** How many of its last 战术板 lines a coach sees, so it doesn't repeat itself. */
const RECENT_NOTES = 7;

/** What one run of the coach did. */
export interface CoachRun {
  /** Whether coaching is on; off, a run does nothing. */
  readonly coaching: boolean;
  /** Squads coached now. */
  readonly squads: number;
  /** Wakes this run queued. */
  readonly queued: number;
  /** Wakes this run finished. */
  readonly done: number;
  /** Wakes whose run failed; each is tried again up to its third try. */
  readonly failed: number;
}

export interface CoachWakes {
  /**
   * Queues the wakes due for every squad that hired a coach, then runs the oldest waiting ones,
   * a squad's one after another. Meant to run every 10 minutes or so.
   */
  run(): Promise<CoachRun>;
  /**
   * Answers a member's reply to a coach under a check-in at once: for each squad whose coach it
   * is and who spoke to that check-in, queues the reply's wake and runs the squad's waiting
   * wakes. Does nothing while coaching is off. What doesn't finish now, the next `run` does.
   */
  answer(input: {
    readonly checkIn: string;
    readonly comment: string;
    readonly coach: string;
  }): Promise<void>;
}

export interface CoachWakesDependencies {
  readonly settings: CoachSettingsStore;
  readonly catalog: CoachCatalogStore;
  readonly stores: CoachStores;
  readonly transaction: CoachTransaction;
  readonly agent: CoachAgent;
  readonly squadWeek: SquadWeekSource;
  readonly aiConsented: AiConsented;
  readonly hiring: CoachHiringStore;
  readonly clock: () => Date;
  /** Told each reply to a check-in once it is saved; the server tells its author. */
  readonly replied?: CoachReplied;
  /** Told each answer to a member's reply once it is saved; the server tells that member. */
  readonly answered?: CoachAnswered;
}

/** An answer the coach just saved to a member's reply to it. */
export type CoachAnswered = (answer: {
  readonly squad: SquadId;
  readonly checkIn: string;
  /** The reply it answers, and who wrote it. */
  readonly comment: string;
  readonly commenter: string;
  readonly coach: CoachId;
  readonly text: string;
}) => Promise<void>;

/** A reply the coach just saved to a check-in: its line, its emoji or both. */
export type CoachReplied = (reply: {
  readonly squad: SquadId;
  readonly checkIn: string;
  /** Who made the check-in. */
  readonly author: string;
  readonly coach: CoachId;
  readonly text: string | undefined;
  readonly emoji: CoachEmoji | undefined;
}) => Promise<void>;

export function createCoachWakes(deps: CoachWakesDependencies): CoachWakes {
  return {
    run: async () => {
      const now = deps.clock();
      const settings = await deps.settings.current();
      if (!settings.coaching) {
        return { coaching: false, squads: 0, queued: 0, done: 0, failed: 0 };
      }
      // The squads that hired a coach, each with its own; a retired coach keeps working for
      // the squads that have it until they fire it.
      const hired = await deps.hiring.hired();
      const coaches = new Map((await deps.catalog.list()).map((coach) => [coach.id, coach]));
      const squads = [...hired.keys()];
      let queued = 0;
      for (const squad of squads) {
        // Near Monday a member's day may be in the week after New York's, or the one before.
        for (const weekStart of weeksAround(now)) {
          const week = await weekOf(deps, { squad, weekStart });
          // A squad everyone left has no one to coach.
          if (week.members.length === 0) continue;
          queued += await deps.stores.wakes.enqueue(wakesDue({ squad, week, now }), now);
        }
      }
      const { done, failed } = await drain(deps, { squads, hired, coaches, settings, now });
      return { coaching: true, squads: squads.length, queued, done, failed };
    },

    answer: async ({ checkIn, comment, coach }) => {
      const now = deps.clock();
      const settings = await deps.settings.current();
      if (!settings.coaching) return;
      const hired = await deps.hiring.hired();
      const squads: SquadId[] = [];
      for (const [squad, hiredCoach] of hired) {
        if (hiredCoach !== coach) continue;
        // Only where this coach said something to the check-in is there anything to reply to.
        const reply = await deps.stores.replies.find(squad, checkIn);
        if (reply?.coach !== coach) continue;
        await deps.stores.wakes.enqueue(
          [{ squad, reason: { kind: 'comment', checkIn, comment } }],
          now,
        );
        squads.push(squad);
      }
      if (squads.length === 0) return;
      const coaches = new Map((await deps.catalog.list()).map((each) => [each.id, each]));
      await drain(deps, { squads, hired, coaches, settings, now });
    },
  };
}

/**
 * Runs these squads' waiting wakes until none is left or the run's time is up. Each round
 * claims one wake of each of a few squads, so a squad's wakes run one after another, each
 * reading what the last one wrote, and squads run side by side.
 */
async function drain(
  deps: CoachWakesDependencies,
  {
    squads,
    hired,
    coaches,
    settings,
    now,
  }: {
    readonly squads: readonly SquadId[];
    readonly hired: ReadonlyMap<SquadId, CoachId>;
    readonly coaches: ReadonlyMap<CoachId, Coach>;
    readonly settings: CoachSettings;
    readonly now: Date;
  },
): Promise<{ readonly done: number; readonly failed: number }> {
  let done = 0;
  let failed = 0;
  while (deps.clock().getTime() - now.getTime() < RUN_BUDGET_MS) {
    const wakes = await deps.stores.wakes.claim({ squads, limit: AT_ONCE, now: deps.clock() });
    if (wakes.length === 0) break;
    const worked = await Promise.all(
      wakes.map(async (wake) => {
        const hiredCoach = hired.get(wake.squad);
        const coach = hiredCoach === undefined ? undefined : coaches.get(hiredCoach);
        // The database keeps a hired coach one of the coaches; only hired squads' wakes
        // are claimed.
        if (coach === undefined) {
          await deps.stores.wakes.fail(wake.id, 'the squad has no coach');
          return false;
        }
        return runWake(deps, { wake, settings, coach, now });
      }),
    );
    done += worked.filter(Boolean).length;
    failed += worked.filter((each) => !each).length;
  }
  return { done, failed };
}

/**
 * A squad's week as the model may read it: only the words of members with a current AI
 * consent.
 */
async function weekOf(
  deps: CoachWakesDependencies,
  input: { readonly squad: SquadId; readonly weekStart: string },
): Promise<SquadWeek> {
  const week = await deps.squadWeek(input);
  const consented = await deps.aiConsented(week.members.map(({ member }) => member));
  return consentedOnly(week, new Set(consented));
}

/** The week a wake is about: its day's, or the one its check-in is in, if it still is. */
async function wakeWeek(
  deps: CoachWakesDependencies,
  { wake, now }: { readonly wake: Wake; readonly now: Date },
): Promise<SquadWeek | undefined> {
  const { reason } = wake;
  if (reason.kind === 'daily') {
    return weekOf(deps, { squad: wake.squad, weekStart: weekStartOf(reason.day) });
  }
  for (const weekStart of weeksAround(now)) {
    const week = await weekOf(deps, { squad: wake.squad, weekStart });
    if (week.checkIns.some(({ id }) => id === reason.checkIn)) return week;
  }
  return undefined;
}

/**
 * Runs one wake: the coach reads the squad's week and files and does what it decides. Its
 * tokens are recorded first, whatever happens next; then its changes and the wake's end are
 * saved together. Says whether it worked.
 */
async function runWake(
  deps: CoachWakesDependencies,
  {
    wake,
    settings,
    coach,
    now,
  }: {
    readonly wake: Wake;
    readonly settings: CoachSettings;
    readonly coach: Coach;
    readonly now: Date;
  },
): Promise<boolean> {
  try {
    const week = await wakeWeek(deps, { wake, now });
    // Nothing to wake for: the check-in went, is no longer shared, or its week is over.
    if (week === undefined) {
      await deps.stores.wakes.finish(wake.id);
      return true;
    }
    const roster = rosterOf(week);
    // The files as the model reads them, by stored path, with members by their names now.
    const stored = new Map(
      [...(await deps.stores.memory.files(wake.squad))].map(([path, body]) => [
        path,
        shownBody(body, roster),
      ]),
    );
    const thread = await threadOf(deps, { wake, week, coach });
    // A reply's wake with nothing to answer: the reply went, or isn't to this squad's coach.
    if (wake.reason.kind === 'comment' && thread === undefined) {
      await deps.stores.wakes.finish(wake.id);
      return true;
    }
    const draft: WakeDraft = {
      files: new Map(stored),
      changed: new Set(),
      note: undefined,
      reply: undefined,
      reaction: undefined,
      answer: undefined,
    };
    const daily = wake.reason.kind === 'daily';
    const files = new Map(
      shownPaths(roster).map((path) => {
        const at = storedPathOf(path, roster);
        return [path, at === undefined ? undefined : stored.get(at)];
      }),
    );
    const task = taskOf({
      reason: wake.reason,
      week,
      files,
      recentNotes: daily ? await deps.stores.notes.recent(wake.squad, RECENT_NOTES) : [],
      ...(thread === undefined ? {} : { thread: thread.thread }),
    });
    if (task === undefined) {
      await deps.stores.wakes.finish(wake.id);
      return true;
    }
    const run = await deps.agent.run({
      model: settings.model,
      instructions: instructionsOf(settings, coach),
      task,
      tools: toolbox({ week, roster, draft, kind: wake.reason.kind }),
      // Every wake of a coach begins with its same instructions, then its tools (each kind's own
      // last: the daily wake's post_note, a check-in's reply and react, a reply's answer), so
      // every kind shares the rest.
      cacheKey: `coach:${coach.id}`,
    });
    // The tokens were spent whatever comes next, so they are counted first, on their own.
    await deps.stores.usage.record({
      squad: wake.squad,
      wake: wake.id,
      coach: coach.id,
      model: settings.model,
      usage: run.usage,
      costMicros: costMicros(run.usage, settings),
    });
    if (!run.ok) {
      await deps.stores.wakes.fail(wake.id, run.error);
      return false;
    }
    const saved = await deps.transaction(async (stores) => {
      const saved = await saveDraft(stores, {
        squad: wake.squad,
        wake,
        draft,
        stored,
        roster,
        coach,
      });
      await stores.wakes.finish(wake.id);
      return saved;
    });
    // After the save, and never undoing it: telling the member is the caller's to log if it fails.
    const { reply, answer } = saved;
    const author = week.checkIns.find(({ id }) => id === reply?.checkIn)?.member;
    if (reply !== undefined && author !== undefined) {
      await deps.replied?.({ ...reply, author }).catch(() => undefined);
    }
    if (answer !== undefined && thread !== undefined) {
      await deps.answered?.({ ...answer, commenter: thread.commenter }).catch(() => undefined);
    }
    return true;
  } catch (error) {
    await deps.stores.wakes.fail(wake.id, error instanceof Error ? error.message : String(error));
    return false;
  }
}

/**
 * Saves what a wake's run changed: a new version of each file whose text it changed (none for
 * an edit it undid), on a daily wake its 战术板 line, and on a check-in's wake its reply, which
 * it answers with when it was saved.
 */
async function saveDraft(
  stores: CoachStores,
  {
    squad,
    wake,
    draft,
    stored,
    roster,
    coach,
  }: {
    readonly squad: SquadId;
    readonly wake: Wake;
    readonly draft: WakeDraft;
    /** The files as the run found them, as the model read them. */
    readonly stored: ReadonlyMap<StoredPath, string>;
    readonly roster: ReadonlyMap<string, string>;
    readonly coach: Coach;
  },
): Promise<{
  readonly reply?: Omit<Parameters<CoachReplied>[0], 'author'>;
  readonly answer?: Omit<Parameters<CoachAnswered>[0], 'commenter'>;
}> {
  const files = [...draft.changed]
    .map((path) => ({ path, body: draft.files.get(path) ?? '' }))
    .filter(({ path, body }) => body !== (stored.get(path) ?? ''))
    .map(({ path, body }) => ({ path, body: storedBody(body, roster) }));
  if (files.length > 0) await stores.memory.save({ squad, wake: wake.id, files });
  if (draft.note !== undefined && wake.reason.kind === 'daily') {
    await stores.notes.save({
      squad,
      coach: coach.id,
      day: wake.reason.day,
      text: draft.note,
      wake: wake.id,
    });
  }
  if (
    wake.reason.kind === 'checkIn' &&
    (draft.reply !== undefined || draft.reaction !== undefined)
  ) {
    const reply = {
      squad,
      checkIn: wake.reason.checkIn,
      coach: coach.id,
      text: draft.reply,
      emoji: draft.reaction,
    };
    if (await stores.replies.save({ ...reply, wake: wake.id })) return { reply };
  }
  if (wake.reason.kind === 'comment' && draft.answer !== undefined) {
    const answer = {
      squad,
      checkIn: wake.reason.checkIn,
      comment: wake.reason.comment,
      coach: coach.id,
      text: draft.answer,
    };
    if (await stores.answers.save({ ...answer, wake: wake.id })) return { answer };
  }
  return {};
}

/**
 * On a reply's wake, what was said under its check-in for the coach to go on: its own reply,
 * then members' replies to it and its answers, up to the one to answer; with who wrote that.
 * `undefined` on another wake, or when there is nothing to answer: the reply went (or its writer
 * withdrew their AI consent), was answered already, isn't to this coach or from this squad, or
 * the coach said nothing to the check-in in this squad.
 */
async function threadOf(
  deps: CoachWakesDependencies,
  { wake, week, coach }: { readonly wake: Wake; readonly week: SquadWeek; readonly coach: Coach },
): Promise<{ readonly thread: CoachThread; readonly commenter: string } | undefined> {
  const { reason } = wake;
  if (reason.kind !== 'comment') return undefined;
  const comments = week.checkIns.find(({ id }) => id === reason.checkIn)?.comments ?? [];
  const answering = comments.find(({ id }) => id === reason.comment);
  if (answering?.toCoach !== coach.id) return undefined;
  // A check-in shared to several squads is answered only in the writer's own.
  if (!week.members.some(({ member }) => member === answering.member)) return undefined;
  const reply = await deps.stores.replies.find(wake.squad, reason.checkIn);
  if (reply?.coach !== coach.id || reply.text === undefined) return undefined;
  const answers = await deps.stores.answers.ofCheckIn(wake.squad, reason.checkIn);
  if (answers.some(({ comment }) => comment === reason.comment)) return undefined;
  // Each answer right after the reply it answers.
  const answerOf = new Map(answers.map(({ comment, text }) => [comment, text]));
  const said = comments
    .filter(({ toCoach, at }) => toCoach === coach.id && at <= answering.at)
    .flatMap(({ id, member, text }) => {
      const answer = answerOf.get(id);
      return [
        { member, text, ...(id === answering.id ? { answering: true } : {}) },
        ...(answer === undefined ? [] : [{ member: undefined, text: answer }]),
      ];
    });
  return { thread: { reply: reply.text, said }, commenter: answering.member };
}
