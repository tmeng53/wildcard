import type { Coach } from '../domain/coach.js';
import { shownPaths, storedPathOf } from '../domain/memory.js';
import { instructionsOf, taskOf } from '../domain/prompt.js';
import type { CoachSettings, SquadId } from '../domain/settings.js';
import { rosterOf } from '../domain/squad-week.js';
import { costMicros, newYorkTime, wakesDue, weekStartOf, type Wake } from '../domain/wake.js';
import type {
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
 * How many wakes one run claims, so a run ends well inside the scheduler's 5 minutes; the rest
 * wait for the next run.
 */
const WAKES_PER_RUN = 12;

/** How many squads' wakes run at once. */
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
   * Queues the wakes due for every squad that hired a coach, then runs the oldest waiting ones. Meant to run
   * every 10 minutes or so.
   */
  run(now: Date): Promise<CoachRun>;
}

export interface CoachWakesDependencies {
  readonly settings: CoachSettingsStore;
  readonly catalog: CoachCatalogStore;
  readonly stores: CoachStores;
  readonly transaction: CoachTransaction;
  readonly agent: CoachAgent;
  readonly squadWeek: SquadWeekSource;
  readonly hiring: CoachHiringStore;
}

export function createCoachWakes(deps: CoachWakesDependencies): CoachWakes {
  return {
    run: async (now) => {
      const settings = await deps.settings.current();
      if (!settings.coaching) {
        return { coaching: false, squads: 0, queued: 0, done: 0, failed: 0 };
      }
      const weekStart = weekStartOf(newYorkTime(now).day);
      // The squads that hired a coach, each with its own; a retired coach keeps working for
      // the squads that have it until they fire it.
      const hired = await deps.hiring.hired();
      const coaches = new Map((await deps.catalog.list()).map((coach) => [coach.id, coach]));
      const squads = [...hired.keys()];
      let queued = 0;
      for (const squad of squads) {
        const week = await deps.squadWeek({ squad, weekStart });
        // A squad everyone left has no one to coach.
        if (week.members.length === 0) continue;
        queued += await deps.stores.wakes.enqueue(wakesDue({ squad, week, now }), now);
      }
      const wakes = await deps.stores.wakes.claim({ squads, limit: WAKES_PER_RUN, now });
      // A squad's wakes run one after another, each reading what the last one wrote; squads
      // run side by side.
      const bySquad = new Map<SquadId, Wake[]>();
      for (const wake of wakes) bySquad.set(wake.squad, [...(bySquad.get(wake.squad) ?? []), wake]);
      const queues = [...bySquad.values()];
      let done = 0;
      let failed = 0;
      for (let start = 0; start < queues.length; start += AT_ONCE) {
        await Promise.all(
          queues.slice(start, start + AT_ONCE).map(async (queue) => {
            for (const wake of queue) {
              const hiredCoach = hired.get(wake.squad);
              const coach = hiredCoach === undefined ? undefined : coaches.get(hiredCoach);
              // The database keeps a hired coach one of the coaches; only hired squads' wakes
              // are claimed.
              if (coach === undefined) {
                await deps.stores.wakes.fail(wake.id, 'the squad has no coach');
                failed += 1;
              } else if (await runWake(deps, { wake, settings, coach, weekStart })) done += 1;
              else failed += 1;
            }
          }),
        );
      }
      return { coaching: true, squads: squads.length, queued, done, failed };
    },
  };
}

/**
 * Runs one wake: the coach reads the squad's week and files and does what it decides, and
 * then its changes, its tokens and the wake's end are saved together. Says whether it worked.
 */
async function runWake(
  deps: CoachWakesDependencies,
  {
    wake,
    settings,
    coach,
    weekStart,
  }: {
    readonly wake: Wake;
    readonly settings: CoachSettings;
    readonly coach: Coach;
    readonly weekStart: string;
  },
): Promise<boolean> {
  try {
    const week = await deps.squadWeek({ squad: wake.squad, weekStart });
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
    // Nothing to wake for: the check-in went, or belongs to a week already over.
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
    const usage = {
      squad: wake.squad,
      wake: wake.id,
      coach: coach.id,
      model: settings.model,
      usage: run.usage,
      costMicros: costMicros(run.usage, settings),
    };
    if (!run.ok) {
      await deps.transaction(async (stores) => {
        await stores.usage.record(usage);
        await stores.wakes.fail(wake.id, run.error);
      });
      return false;
    }
    await deps.transaction(async (stores) => {
      await saveDraft(stores, { squad: wake.squad, wake, draft, coach });
      await stores.usage.record(usage);
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
