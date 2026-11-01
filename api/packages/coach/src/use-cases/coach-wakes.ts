import type { Coach } from '../domain/coach.js';
import { shownPaths, storedPathOf } from '../domain/memory.js';
import { instructionsOf, taskOf } from '../domain/prompt.js';
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
}

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
      // Each round claims one wake of each of a few squads, so a squad's wakes run one after
      // another, each reading what the last one wrote, and squads run side by side.
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
      return { coaching: true, squads: squads.length, queued, done, failed };
    },
  };
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
    const stored = await deps.stores.memory.files(wake.squad);
    const draft: WakeDraft = { files: new Map(stored), changed: new Set(), note: undefined };
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
    });
    if (task === undefined) {
      await deps.stores.wakes.finish(wake.id);
      return true;
    }
    const run = await deps.agent.run({
      model: settings.model,
      instructions: instructionsOf(settings, coach),
      task,
      tools: toolbox({ week, roster, draft, daily }),
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
    await deps.transaction(async (stores) => {
      await saveDraft(stores, { squad: wake.squad, wake, draft, coach });
      await stores.wakes.finish(wake.id);
    });
    return true;
  } catch (error) {
    await deps.stores.wakes.fail(wake.id, error instanceof Error ? error.message : String(error));
    return false;
  }
}

/** Saves what a wake's run changed: its files and, on a daily wake, its 战术板 line. */
async function saveDraft(
  stores: CoachStores,
  {
    squad,
    wake,
    draft,
    coach,
  }: {
    readonly squad: SquadId;
    readonly wake: Wake;
    readonly draft: WakeDraft;
    readonly coach: Coach;
  },
): Promise<void> {
  const files = [...draft.changed].map((path) => ({ path, body: draft.files.get(path) ?? '' }));
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
}
