import { challengeOpen, type Challenge } from '../domain/challenge.js';
import { coachIn, type Coach, type CoachId } from '../domain/coach.js';
import {
  shownBody,
  shownPaths,
  squadSeed,
  storedBody,
  storedPathOf,
  type StoredPath,
} from '../domain/memory.js';
import {
  instructionsOf,
  taskOf,
  type CoachThread,
  type DayTalk,
  type YesterdayFacts,
} from '../domain/prompt.js';
import type { CoachEmoji } from '../domain/reply.js';
import { holidaysOn, SquadId, type CoachSettings } from '../domain/settings.js';
import { factsText, planIndexOf, type NoteBrief } from '../domain/member-facts.js';
import {
  consentedOnly,
  languageOf,
  rosterOf,
  saidTo,
  weekText,
  type SquadWeek,
} from '../domain/squad-week.js';
import {
  costMicros,
  wakesDue,
  weekStartOf,
  weeksAround,
  type NewWake,
  type Wake,
  type WakeStep,
} from '../domain/wake.js';
import type {
  AiConsented,
  CoachAgent,
  CoachCatalogStore,
  CoachGifting,
  CoachHiringStore,
  CoachMemberFacts,
  CoachMemes,
  CoachWeather,
  CoachOccasions,
  CoachPhotoUrls,
  CoachSettingsStore,
  CoachStores,
  CoachTransaction,
  SquadWeekSource,
} from '../ports.js';
import { toolbox, type WakeDraft } from './coach-wakes/toolbox.js';
import { offDutyWhy } from './off-duty.js';
import { NEW_YORK, wallClockAt } from '@wildcard/time-zones';

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
  /**
   * For testing a prompt (Tracy, 2026-11-08): runs today's daily wake of the member's squad now,
   * for that member alone, and says what the coach would write and give, saving and sending
   * nothing; only its tokens are recorded, against the squad's caps, which it keeps to like any
   * wake. Works while coaching is off too.
   */
  preview(input: { readonly squad: SquadId; readonly member: string }): Promise<CoachPreview>;
}

/** What a daily wake would do for one member, from `CoachWakes.preview`. */
export type CoachPreview =
  | { readonly ran: false; readonly why: string }
  | {
      readonly ran: true;
      readonly day: string;
      /** The 战术板 line it would post for the squad. */
      readonly board?: string;
      /** The morning note (便条) to the member, with its challenge, if any. */
      readonly note?: { readonly text: string; readonly challenge?: Challenge };
      /** Why no note: the member hasn't agreed to AI use, or turned the coach's messages off. */
      readonly noNote?: string;
      /** The gift it would give the member, and why none when the member can't get one. */
      readonly gift?: { readonly piece: string; readonly line: string };
      readonly noGift?: string;
      /** The memory files it would change, with their new bodies as the model wrote them. */
      readonly files: readonly { readonly path: string; readonly body: string }[];
      readonly steps: readonly WakeStep[];
      readonly costMicros: number;
      /** Set when the model's run failed; the rest is what it got to before. */
      readonly error?: string;
    };

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
  /**
   * Each squad's time zone at a moment (小队时区), the clock of its daily wake and of the day it
   * tells the coach; without it, New York's.
   */
  readonly timeZonesAt?: (
    squads: readonly SquadId[],
    moment: Date,
  ) => Promise<ReadonlyMap<string, string>>;
  /** Without it the coach has no meme library to draw humour from. */
  readonly memes?: CoachMemes;
  /** Without it the coach doesn't know anyone's weather. */
  readonly weatherOf?: CoachWeather;
  /** Without it the coach is told of no holiday or other moment. */
  readonly occasions?: CoachOccasions;
  /** Told each reply to a check-in once it is saved; the server tells its author. */
  readonly replied?: CoachReplied;
  /** Told each answer to a member's reply once it is saved; the server tells that member. */
  readonly answered?: CoachAnswered;
  /**
   * Of these members, the ones who keep the coach's messages on: only they get a morning note.
   * Without it every member who agreed to AI use gets one.
   */
  readonly wantNotes?: (members: readonly string[]) => Promise<readonly string[]>;
  /** Without it the coach gives no gifts. */
  readonly gifting?: CoachGifting;
  /** Told what went wrong after a wake's save, such as a gift that couldn't be given. */
  readonly warn?: (message: string, details: Record<string, unknown>) => void;
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
  /** Whom it @s, by member id: the server tells them too. */
  readonly mentions: readonly string[];
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
  /** Whom its line @s, by member id: the server tells them too. */
  readonly mentions: readonly string[];
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
      const zones = (await deps.timeZonesAt?.(squads, now)) ?? new Map<string, string>();
      for (const squad of squads) {
        const timeZone = zones.get(squad) ?? NEW_YORK;
        // Near Monday a member's day may be in the week after New York's, or the one before.
        for (const weekStart of weeksAround(now)) {
          const week = await weekOf(deps, { squad, weekStart });
          // A squad everyone left has no one to coach.
          if (week.members.length === 0) continue;
          queued += await deps.stores.wakes.enqueue(wakesDue({ squad, week, now, timeZone }), now);
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

    preview: async ({ squad, member }) => previewDaily(deps, { squad, member }),
  };
}

async function previewDaily(
  deps: CoachWakesDependencies,
  { squad, member }: { readonly squad: SquadId; readonly member: string },
): Promise<CoachPreview> {
  const now = deps.clock();
  const settings = await deps.settings.current();
  const hiredCoach = (await deps.hiring.hired()).get(squad);
  const coach = (await deps.catalog.list()).find(({ id }) => id === hiredCoach);
  if (coach === undefined) return { ran: false, why: 'the squad has no coach' };
  const offDuty = await offDutyWhy(
    { usage: deps.stores.usage, clock: deps.clock, timeZonesAt: deps.timeZonesAt },
    { squad, settings },
  );
  if (offDuty !== undefined) return { ran: false, why: `off duty today: ${offDuty}` };
  const zone = (await deps.timeZonesAt?.([squad], now))?.get(squad) ?? NEW_YORK;
  const day = wallClockAt(now, zone).day;
  const week = await weekOf(deps, { squad, weekStart: weekStartOf(day) });
  if (!week.members.some((each) => each.member === member)) {
    return { ran: false, why: 'the member is not in the squad' };
  }
  const thought = await think(deps, {
    wake: { squad, reason: { kind: 'daily', day } },
    settings,
    coach,
    now,
    only: member,
  });
  if (thought === undefined) return { ran: false, why: 'nothing to wake for' };
  const { run, draft, roster } = thought;
  const note = draft.memberNotes.get(member);
  const gift = draft.gifts.get(member);
  const reads = await noteReaders(deps, [member]);
  const giftable =
    deps.gifting === undefined
      ? false
      : (await deps.gifting.options({ squad, members: await deps.aiConsented([member]) })).open.has(
          member,
        );
  return {
    ran: true,
    day,
    ...(draft.note === undefined ? {} : { board: draft.note }),
    ...(note === undefined
      ? reads.length === 0
        ? { noNote: 'the member has not agreed to AI use, or turned the coach’s messages off' }
        : {}
      : { note }),
    ...(gift === undefined
      ? giftable
        ? {}
        : { noGift: 'no gift can go to the member now (one a week, or no AI consent)' }
      : { gift }),
    files: [...draft.changed].map((path) => ({
      path,
      body: shownBody(draft.files.get(path) ?? '', roster),
    })),
    steps: draft.steps,
    costMicros: costMicros(run.usage, settings),
    ...(run.ok ? {} : { error: run.error }),
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
  { wake, now }: { readonly wake: NewWake; readonly now: Date },
): Promise<SquadWeek | undefined> {
  const { reason } = wake;
  if (reason.kind === 'daily' || reason.kind === 'dream') {
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

/** A wake as `think` runs it: one from the queue, or a preview's, which has no id. */
type Thought = NewWake & { readonly id?: number };

/** What the coach did on a run, before any of it is saved. */
interface Thinking {
  readonly run: Awaited<ReturnType<CoachAgent['run']>>;
  readonly draft: WakeDraft;
  readonly stored: ReadonlyMap<StoredPath, string>;
  readonly roster: ReturnType<typeof rosterOf>;
  readonly thread: Awaited<ReturnType<typeof threadOf>>;
  readonly author: string | undefined;
  readonly challenge: Awaited<ReturnType<CoachStores['memberNotes']['challengeOf']>>;
  readonly day: string;
}

/** These members, or only `only` of them when it is given. */
function onlyFor(members: readonly string[], only: string | undefined): readonly string[] {
  return only === undefined ? members : members.filter((member) => member === only);
}

/**
 * The coach reads the squad's week and files and decides what to do, into a draft nothing has
 * saved yet; its tokens are recorded, whatever comes next. Undefined when there is nothing to
 * wake for. With `only`, a daily wake writes a note to and may give a gift to that member alone.
 */
async function think(
  deps: CoachWakesDependencies,
  {
    wake,
    settings,
    coach,
    now,
    only,
  }: {
    readonly wake: Thought;
    readonly settings: CoachSettings;
    readonly coach: Coach;
    readonly now: Date;
    readonly only?: string;
  },
): Promise<Thinking | undefined> {
  const week = await wakeWeek(deps, { wake, now });
  // Nothing to wake for: the check-in went, is no longer shared, or its week is over.
  if (week === undefined) return undefined;
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
  if (wake.reason.kind === 'comment' && thread === undefined) return undefined;
  const draft: WakeDraft = {
    files: new Map(stored),
    changed: new Set(),
    note: undefined,
    memberNotes: new Map(),
    gifts: new Map(),
    reply: undefined,
    replyMentions: [],
    reaction: undefined,
    answer: undefined,
    answerMentions: [],
    challengeDone: false,
    steps: [],
  };
  // A squad whose coach hasn't written its file yet starts from its name and who is in it,
  // saved with the run's other changes.
  if ((stored.get(SEEDED) ?? '') === '') {
    draft.files.set(SEEDED, squadSeed(week, roster));
    draft.changed.add(SEEDED);
  }
  const daily = wake.reason.kind === 'daily';
  // The daily wake and the night's dream both look back at the day before.
  const looksBack = daily || wake.reason.kind === 'dream';
  // Who the daily wake writes a morning note to: every member who agreed to AI use and keeps
  // the coach's messages on (Tracy, 2026-11-07: switched off, the note stops altogether).
  const noteTo = daily
    ? await noteReaders(
        deps,
        onlyFor(
          week.members.map(({ member }) => member),
          only,
        ),
      )
    : [];
  const files = new Map(
    shownPaths(roster).map((path) => {
      const at = storedPathOf(path, roster);
      return [path, at === undefined ? undefined : draft.files.get(at)];
    }),
  );
  // The day the wake is for: the daily wake's own, or the squad's today on its own clock.
  const zone = (await deps.timeZonesAt?.([wake.squad], now))?.get(wake.squad) ?? NEW_YORK;
  const day =
    wake.reason.kind === 'daily' || wake.reason.kind === 'dream'
      ? wake.reason.day
      : wallClockAt(now, zone).day;
  // Who may get a gift today: members who agreed to AI use and got none this week.
  const gifting =
    daily && deps.gifting !== undefined
      ? await deps.gifting.options({
          squad: wake.squad,
          members: await deps.aiConsented(
            onlyFor(
              week.members.map(({ member }) => member),
              only,
            ),
          ),
        })
      : undefined;
  // On a check-in's wake, the challenge its author got on today's note and what they said.
  const author = addresseeOf(week, wake.reason);
  const challenge =
    wake.reason.kind === 'checkIn' && author !== undefined
      ? await deps.stores.memberNotes.challengeOf({ squad: wake.squad, member: author, day })
      : undefined;
  const task = taskOf({
    reason: wake.reason,
    week,
    files,
    // The holidays from the coach's calendar, then the app's own moments (a store open).
    occasions: [
      ...new Set([...holidaysOn(settings.holidays, day), ...((await deps.occasions?.(day)) ?? [])]),
    ],
    backAgain: await deps.hiring.backAgain(wake.squad),
    recentNotes: daily ? await deps.stores.notes.recent(wake.squad, RECENT_NOTES) : [],
    ...(thread === undefined ? {} : { thread: thread.thread }),
    canSeePhotos: deps.photoUrls !== undefined,
    ...(challenge === undefined
      ? {}
      : {
          challenge: {
            challenge: challenge.challenge,
            ...(challenge.answer === undefined ? {} : { answer: challenge.answer }),
            ...(challenge.reason === undefined ? {} : { reason: challenge.reason }),
            ...(challenge.completion === undefined ? {} : { completion: challenge.completion }),
          },
        }),
    ...(gifting === undefined ? {} : { gifting }),
    recentEmoji:
      wake.reason.kind === 'checkIn'
        ? await deps.stores.replies.recent(wake.squad, RECENT_EMOJI)
        : [],
    talks: looksBack ? await talksOf(deps, { squad: wake.squad, week, coach, now }) : [],
    ...(wake.reason.kind === 'daily'
      ? {
          noteTo: await briefsOf(deps, {
            squad: wake.squad,
            week,
            roster,
            members: noteTo,
            day: wake.reason.day,
          }),
        }
      : {}),
    ...(looksBack ? { yesterday: await yesterdayOf(deps, { squad: wake.squad, week, day }) } : {}),
  });
  if (task === undefined) return undefined;
  const run = await deps.agent.run({
    model: settings.model,
    // It goes by its name in the squad's language (Tracy, 2026-11-08: Poki in English).
    instructions: instructionsOf(settings, coachIn(coach, week.language ?? 'zh-Hans')),
    task,
    tools: toolbox({
      week,
      roster,
      draft,
      kind: wake.reason.kind,
      to: author,
      // Only for a post made today: one from before midnight didn't do today's challenge.
      openChallenge:
        challenge !== undefined &&
        challengeOpen(challenge) &&
        postedOn({ week, reason: wake.reason, day, zone }),
      ...photosOf(deps.photoUrls, { week, wake }),
      ...factsFor(deps, { squad: wake.squad, week, roster }),
      ...(deps.memes === undefined ? {} : { memes: deps.memes }),
      noteTo,
      ...(gifting === undefined ? {} : { gifting }),
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
    ...(wake.id === undefined ? {} : { wake: wake.id }),
    coach: coach.id,
    model: settings.model,
    usage: run.usage,
    costMicros: costMicros(run.usage, settings),
    at: deps.clock(),
  });
  return { run, draft, stored, roster, thread, author, challenge, day };
}

/**
 * Runs one wake: the coach thinks (its tokens recorded first, whatever happens next), then its
 * changes and the wake's end are saved together. Says whether it worked.
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
    const offDuty = await offDutyWhy(
      { usage: deps.stores.usage, clock: deps.clock, timeZonesAt: deps.timeZonesAt },
      { squad: wake.squad, settings },
    );
    if (offDuty !== undefined) {
      await deps.stores.wakes.skip(wake.id, offDuty);
      return true;
    }
    const thought = await think(deps, { wake, settings, coach, now });
    if (thought === undefined) {
      await deps.stores.wakes.finish(wake.id);
      return true;
    }
    const { run, draft, stored, roster, thread, author, challenge, day } = thought;
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
        ...(challenge === undefined ? {} : { challenge: { note: challenge.note, day } }),
        stored,
        roster,
        coach,
      });
      await stores.wakes.finish(wake.id);
      return saved;
    });
    // After the save, and never undoing it: telling the member is the caller's to log if it fails.
    const { reply, answer } = saved;
    if (reply !== undefined && author !== undefined) {
      await deps.replied?.({ ...reply, author }).catch(() => undefined);
    }
    if (answer !== undefined && thread !== undefined) {
      await deps.answered?.({ ...answer, commenter: thread.commenter }).catch(() => undefined);
    }
    // Gifts are the unlocks module's, given after the run's save; one refused is only noted.
    for (const [member, { piece, line }] of draft.gifts) {
      const refused = await deps.gifting
        ?.give({ squad: wake.squad, member, coach: coach.id, piece, line })
        .catch((error: unknown) => (error instanceof Error ? error.message : String(error)));
      if (refused !== undefined) {
        deps.warn?.('coach gift not given', { squad: wake.squad, member, piece, refused });
      }
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
  {
    squad,
    week,
    roster,
  }: {
    readonly squad: string;
    readonly week: SquadWeek;
    readonly roster: ReadonlyMap<string, string>;
  },
): { readonly facts?: () => Promise<string> } {
  const { memberFacts } = deps;
  if (memberFacts === undefined) return {};
  return {
    facts: async () => {
      const all = week.members.map(({ member }) => member);
      const consented = new Set(await deps.aiConsented(all));
      const members = all.filter((member) => consented.has(member));
      return factsText(await memberFacts({ squad, members, weekStart: week.weekStart }), roster);
    },
  };
}

/**
 * What the daily wake tells the coach about each member it writes a morning note to: today's
 * plan, this week's 饮食小目标 and how many days they trained so far, so it needn't look them up.
 * Without the plans (no `memberFacts`, or they can't be read), only the days trained.
 */
async function briefsOf(
  deps: CoachWakesDependencies,
  {
    squad,
    week,
    roster,
    members,
    day,
  }: {
    readonly squad: string;
    readonly week: SquadWeek;
    readonly roster: ReadonlyMap<string, string>;
    readonly members: readonly string[];
    readonly day: string;
  },
): Promise<readonly NoteBrief[]> {
  const facts =
    members.length === 0 || deps.memberFacts === undefined
      ? []
      : await deps.memberFacts({ squad, members, weekStart: week.weekStart }).catch(() => []);
  const today = planIndexOf(day);
  // The weather is a nice-to-have: a morning note goes out without it.
  const weather =
    members.length === 0 || deps.weatherOf === undefined
      ? new Map<string, string>()
      : await deps.weatherOf({ members, day }).catch(() => new Map<string, string>());
  return members.flatMap((member): NoteBrief[] => {
    const name = roster.get(member);
    if (name === undefined) return [];
    const trainedDays = new Set(
      week.checkIns
        .filter((each) => each.member === member && each.kind === 'trained')
        .map((each) => each.day),
    ).size;
    const mine = facts.find((each) => each.member === member);
    const planned = mine?.plan[today];
    return [
      {
        name,
        language: languageOf(week, member),
        trainedDays,
        ...(weather.has(member) ? { weather: weather.get(member) } : {}),
        ...(mine === undefined || planned === undefined
          ? {}
          : { plan: { today: planned, fuelGoals: mine.fuelGoals } }),
      },
    ];
  });
}

/** The squad's posts of the day before `day`: made for it, or posted on it. */
async function yesterdayOf(
  deps: CoachWakesDependencies,
  { squad, week, day }: { readonly squad: SquadId; readonly week: SquadWeek; readonly day: string },
): Promise<YesterdayFacts> {
  const yesterday = dayBefore(day, 1);
  // On a Monday, yesterday was last week.
  const weekStart = weekStartOf(yesterday);
  const its = weekStart === week.weekStart ? week : await weekOf(deps, { squad, weekStart });
  // The day's challenges and what each member said to them, why they let one go included, only
  // for members who still agree to AI use.
  const set = await deps.stores.memberNotes.challengesOn({ squad, day: yesterday });
  const consented = new Set(await deps.aiConsented(set.map(({ member }) => member)));
  return {
    day: yesterday,
    checkIns: its.checkIns.filter((each) => each.day === yesterday || each.postedDay === yesterday),
    challenges: set.filter(({ member }) => consented.has(member)),
  };
}

/** Whether the check-in a wake is about was posted on `day`, on the squad's clock. */
function postedOn({
  week,
  reason,
  day,
  zone,
}: {
  readonly week: SquadWeek;
  readonly reason: Wake['reason'];
  readonly day: string;
  readonly zone: string;
}): boolean {
  if (reason.kind !== 'checkIn') return false;
  const posted = week.checkIns.find(({ id }) => id === reason.checkIn)?.createdAt;
  return posted !== undefined && wallClockAt(posted, zone).day === day;
}

/** `YYYY-MM-DD`, `days` before `day`. */
function dayBefore(day: string, days: number): string {
  return new Date(Date.parse(`${day}T00:00:00Z`) - days * 86_400_000).toISOString().slice(0, 10);
}

/** The photos of the check-in a wake is about, to look at on demand, when it has any. */
function photosOf(
  photoUrls: CoachPhotoUrls | undefined,
  { week, wake }: { readonly week: SquadWeek; readonly wake: NewWake },
): { readonly photos?: () => Promise<readonly string[]> } {
  if (photoUrls === undefined || wake.reason.kind === 'daily' || wake.reason.kind === 'dream') {
    return {};
  }
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
    challenge,
  }: {
    readonly squad: SquadId;
    readonly wake: Wake;
    readonly draft: WakeDraft;
    /** On a check-in's wake, the note whose challenge its author has today, and that day. */
    readonly challenge?: { readonly note: number; readonly day: string };
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
  if (wake.reason.kind === 'daily') {
    for (const [member, { text, challenge }] of draft.memberNotes) {
      await stores.memberNotes.save({
        squad,
        member,
        coach: coach.id,
        day: wake.reason.day,
        text,
        ...(challenge === undefined ? {} : { challenge }),
        wake: wake.id,
      });
    }
  }
  if (wake.reason.kind === 'checkIn' && draft.challengeDone && challenge !== undefined) {
    await stores.memberNotes.complete({ ...challenge, by: 'coach' });
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
      mentions: draft.replyMentions,
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
      mentions: draft.answerMentions,
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
  {
    wake,
    week,
    coach,
  }: { readonly wake: NewWake; readonly week: SquadWeek; readonly coach: Coach },
): Promise<{ readonly thread: CoachThread; readonly commenter: string } | undefined> {
  const { reason } = wake;
  if (reason.kind !== 'comment') return undefined;
  const comments = week.checkIns.find(({ id }) => id === reason.checkIn)?.comments ?? [];
  const answering = comments.find(({ id }) => id === reason.comment);
  if (answering === undefined || saidTo(answering) !== coach.id) return undefined;
  // A comment is answered only in a squad its writer belongs to.
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

/** The members a daily wake writes a morning note to. */
async function noteReaders(
  deps: Pick<CoachWakesDependencies, 'aiConsented' | 'wantNotes'>,
  members: readonly string[],
): Promise<readonly string[]> {
  const consented = await deps.aiConsented(members);
  return deps.wantNotes === undefined ? consented : await deps.wantNotes(consented);
}

/** Whom a line on this wake answers: the check-in's author, or the member who wrote to the coach. */
function addresseeOf(week: SquadWeek, reason: Wake['reason']): string | undefined {
  if (reason.kind === 'checkIn') {
    return week.checkIns.find(({ id }) => id === reason.checkIn)?.member;
  }
  if (reason.kind === 'comment') {
    return week.checkIns
      .find(({ id }) => id === reason.checkIn)
      ?.comments.find(({ id }) => id === reason.comment)?.member;
  }
  return undefined;
}
