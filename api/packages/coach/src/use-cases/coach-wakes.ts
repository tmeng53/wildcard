import type { Coach, CoachId } from '../domain/coach.js';
import {
  shownBody,
  shownPaths,
  squadSeed,
  storedBody,
  storedPathOf,
  type StoredPath,
} from '../domain/memory.js';
import { instructionsOf, taskOf, type CoachThread, type DayTalk } from '../domain/prompt.js';
import type { CoachEmoji } from '../domain/reply.js';
import { SquadId, type CoachSettings } from '../domain/settings.js';
import { factsText } from '../domain/member-facts.js';
import { consentedOnly, rosterOf, saidTo, weekText, type SquadWeek } from '../domain/squad-week.js';
import { costMicros, wakesDue, weekStartOf, weeksAround, type Wake } from '../domain/wake.js';
import type {
  AiConsented,
  CoachAgent,
  CoachCatalogStore,
  CoachHiringStore,
  CoachMemberFacts,
  CoachPhotoUrls,
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

/** How many of its last reactions a coach sees on a check-in's wake, so it varies them. */
const RECENT_EMOJI = 8;

/** How far back the daily wake reads the talk under check-ins, to remember from it. */
const TALK_WINDOW_MS = 24 * 60 * 60_000;

/** The file a squad's coach starts from: its name and who is in it. */
const SEEDED = 'squad.md';

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
   * Answers a member's reply to a coach, or @ of it, under a check-in at once: for each of
   * `squads` (those the member sees the check-in through) whose coach it is, queues the
   * comment's wake and runs the squad's waiting wakes. Does nothing while coaching is off. What
   * doesn't finish now, the next `run` does.
   */
  answer(input: {
    readonly checkIn: string;
    readonly comment: string;
    readonly coach: string;
    readonly squads: readonly string[];
  }): Promise<void>;
  /**
   * Has the coach of each of these squads that hired one look at a check-in just made, now:
   * queues its wake and runs the squad's waiting wakes. Does nothing while coaching is off. What
   * doesn't finish now, the next `run` does.
   */
  checkedIn(input: {
    readonly checkIn: string;
    readonly squads: readonly SquadId[];
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
  /** Without it the coach never sees photos. */
  readonly photoUrls?: CoachPhotoUrls;
  /** Without it the coach has no member stats or plans to look up. */
  readonly memberFacts?: CoachMemberFacts;
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

    answer: async ({ checkIn, comment, coach, squads: through }) => {
      const now = deps.clock();
      const settings = await deps.settings.current();
      if (!settings.coaching) return;
      const hired = await deps.hiring.hired();
      // The wake itself skips a squad with nothing to answer (a reply to what the coach never
      // said there, or a comment from outside it).
      const squads = through
        .map((squad) => SquadId.parse(squad))
        .filter((squad) => hired.get(squad) === coach);
      if (squads.length === 0) return;
      await deps.stores.wakes.enqueue(
        squads.map((squad) => ({ squad, reason: { kind: 'comment', checkIn, comment } })),
        now,
      );
      const coaches = new Map((await deps.catalog.list()).map((each) => [each.id, each]));
      await drain(deps, { squads, hired, coaches, settings, now });
    },

    checkedIn: async ({ checkIn, squads: sharedTo }) => {
      const now = deps.clock();
      const settings = await deps.settings.current();
      if (!settings.coaching) return;
      const hired = await deps.hiring.hired();
      const squads = sharedTo.filter((squad) => hired.has(squad));
      if (squads.length === 0) return;
      await deps.stores.wakes.enqueue(
        squads.map((squad) => ({ squad, reason: { kind: 'checkIn', checkIn } })),
        now,
      );
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
  // A check-in may count for a day up to a week before it was posted (补打卡), so its week may
  // be the one before.
  const weekBefore = weeksAround(new Date(now.getTime() - 7 * 86_400_000));
  for (const weekStart of new Set([...weeksAround(now), ...weekBefore])) {
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
      steps: [],
    };
    // A squad whose coach hasn't written its file yet starts from its name and who is in it,
    // saved with the run's other changes.
    if ((stored.get(SEEDED) ?? '') === '') {
      draft.files.set(SEEDED, squadSeed(week, roster));
      draft.changed.add(SEEDED);
    }
    const daily = wake.reason.kind === 'daily';
    const files = new Map(
      shownPaths(roster).map((path) => {
        const at = storedPathOf(path, roster);
        return [path, at === undefined ? undefined : draft.files.get(at)];
      }),
    );
    const task = taskOf({
      reason: wake.reason,
      week,
      files,
      recentNotes: daily ? await deps.stores.notes.recent(wake.squad, RECENT_NOTES) : [],
      ...(thread === undefined ? {} : { thread: thread.thread }),
      recentEmoji:
        wake.reason.kind === 'checkIn'
          ? await deps.stores.replies.recent(wake.squad, RECENT_EMOJI)
          : [],
      talks: daily ? await talksOf(deps, { squad: wake.squad, week, coach, now }) : [],
    });
    if (task === undefined) {
      await deps.stores.wakes.finish(wake.id);
      return true;
    }
    const run = await deps.agent.run({
      model: settings.model,
      instructions: instructionsOf(settings, coach),
      task,
      tools: toolbox({
        week,
        roster,
        draft,
        kind: wake.reason.kind,
        ...photosOf(deps.photoUrls, { week, wake }),
        ...factsFor(deps, { week, roster }),
        pastWeek: async (weeksAgo) =>
          weekText(
            await weekOf(deps, {
              squad: wake.squad,
              weekStart: weekStartOf(dayBefore(week.weekStart, weeksAgo * 7)),
            }),
          ),
      }),
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
    await deps.stores.steps.record({ squad: wake.squad, wake: wake.id, steps: draft.steps });
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
 * The stats and this week's plans of the squad's members who agreed to AI use (the others have
 * nothing in the week the model reads), as the `member_stats` tool answers.
 */
function factsFor(
  deps: CoachWakesDependencies,
  { week, roster }: { readonly week: SquadWeek; readonly roster: ReadonlyMap<string, string> },
): { readonly facts?: () => Promise<string> } {
  const { memberFacts } = deps;
  if (memberFacts === undefined) return {};
  return {
    facts: async () => {
      const all = week.members.map(({ member }) => member);
      const consented = new Set(await deps.aiConsented(all));
      const members = all.filter((member) => consented.has(member));
      return factsText(await memberFacts({ members, weekStart: week.weekStart }), roster);
    },
  };
}

/** `YYYY-MM-DD`, `days` before `day`. */
function dayBefore(day: string, days: number): string {
  return new Date(Date.parse(`${day}T00:00:00Z`) - days * 86_400_000).toISOString().slice(0, 10);
}

/** The photos of the check-in a wake is about, to look at on demand, when it has any. */
function photosOf(
  photoUrls: CoachPhotoUrls | undefined,
  { week, wake }: { readonly week: SquadWeek; readonly wake: Wake },
): { readonly photos?: () => Promise<readonly string[]> } {
  if (photoUrls === undefined || wake.reason.kind === 'daily') return {};
  const { checkIn } = wake.reason;
  const paths = week.checkIns.find(({ id }) => id === checkIn)?.photos ?? [];
  return paths.length === 0 ? {} : { photos: () => photoUrls(paths) };
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
 * On a daily wake, what was said under check-ins over the last day (members' comments, and the
 * coach's reply and answers), so the coach can remember what it missed while talking. Looks at
 * this week and the one before, since Monday's wake looks back at Sunday.
 */
async function talksOf(
  deps: CoachWakesDependencies,
  {
    squad,
    week,
    coach,
    now,
  }: {
    readonly squad: SquadId;
    readonly week: SquadWeek;
    readonly coach: Coach;
    readonly now: Date;
  },
): Promise<readonly DayTalk[]> {
  const since = now.getTime() - TALK_WINDOW_MS;
  const before = await weekOf(deps, {
    squad,
    weekStart: weekStartOf(dayBefore(week.weekStart, 7)),
  });
  const talks: DayTalk[] = [];
  const checkIns = new Map([...before.checkIns, ...week.checkIns].map((each) => [each.id, each]));
  for (const checkIn of checkIns.values()) {
    const lately = checkIn.comments.filter(({ at }) => at.getTime() >= since);
    if (lately.length === 0) continue;
    const reply = await deps.stores.replies.find(squad, checkIn.id);
    const answers = new Map(
      (await deps.stores.answers.ofCheckIn(squad, checkIn.id)).map(({ comment, text }) => [
        comment,
        text,
      ]),
    );
    talks.push({
      checkIn,
      ...(reply?.coach === coach.id && reply.text !== undefined ? { reply: reply.text } : {}),
      said: lately.flatMap(({ id, member, text }) => {
        const answer = answers.get(id);
        return [
          { member, text },
          ...(answer === undefined ? [] : [{ member: undefined, text: answer }]),
        ];
      }),
    });
  }
  return talks;
}

/**
 * On a comment's wake (a reply to the coach or an @ of it), what was said under its check-in for
 * the coach to go on: its own reply, when it wrote one, then members' replies and @s to it and
 * its answers, up to the one to answer; with who wrote that. `undefined` on another wake, or
 * when there is nothing to answer: the comment went (or its writer withdrew their AI consent),
 * was answered already, isn't to this coach or from this squad, or replies to what the coach
 * never said to the check-in in this squad.
 */
async function threadOf(
  deps: CoachWakesDependencies,
  { wake, week, coach }: { readonly wake: Wake; readonly week: SquadWeek; readonly coach: Coach },
): Promise<{ readonly thread: CoachThread; readonly commenter: string } | undefined> {
  const { reason } = wake;
  if (reason.kind !== 'comment') return undefined;
  const comments = week.checkIns.find(({ id }) => id === reason.checkIn)?.comments ?? [];
  const answering = comments.find(({ id }) => id === reason.comment);
  if (answering === undefined || saidTo(answering) !== coach.id) return undefined;
  // A check-in shared to several squads is answered only in the writer's own.
  if (!week.members.some(({ member }) => member === answering.member)) return undefined;
  const found = await deps.stores.replies.find(wake.squad, reason.checkIn);
  const reply = found?.coach === coach.id ? found.text : undefined;
  // A reply to the coach needs something it said; an @ doesn't.
  if (answering.toCoach !== undefined && reply === undefined) return undefined;
  const answers = await deps.stores.answers.ofCheckIn(wake.squad, reason.checkIn);
  if (answers.some(({ comment }) => comment === reason.comment)) return undefined;
  // Each answer right after the reply it answers.
  const answerOf = new Map(answers.map(({ comment, text }) => [comment, text]));
  const said = comments
    .filter((each) => saidTo(each) === coach.id && each.at <= answering.at)
    .flatMap(({ id, member, text }) => {
      const answer = answerOf.get(id);
      return [
        { member, text, ...(id === answering.id ? { answering: true } : {}) },
        ...(answer === undefined ? [] : [{ member: undefined, text: answer }]),
      ];
    });
  return {
    thread: { ...(reply === undefined ? {} : { reply }), said },
    commenter: answering.member,
  };
}
