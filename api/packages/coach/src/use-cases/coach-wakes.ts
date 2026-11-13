import { challengeOpen, type Challenge } from '../domain/challenge.js';
import { coachIn, type Coach, type CoachId } from '../domain/coach.js';
import {
  memberOfPath,
  shownBody,
  shownPaths,
  squadSeed,
  storedBody,
  storedPathOf,
  type StoredPath,
} from '../domain/memory.js';
import {
  instructionsOf,
  saidLines,
  taskOf,
  type CoachThread,
  type DayTalk,
  type TookOver,
  type YesterdayFacts,
} from '../domain/prompt.js';
import type { CoachEmoji } from '../domain/reply.js';
import { holidaysOn, SquadId, type CoachSettings } from '../domain/settings.js';
import { factsText, type NoteBrief } from '../domain/member-facts.js';
import {
  consentedOnly,
  dayWords,
  languageOf,
  rosterOf,
  saidTo,
  postWhat,
  type SquadWeek,
  type WeekComment,
} from '../domain/squad-week.js';
import { wakesDue, weeksAround, type NewWake, type Wake, type WakeStep } from '../domain/wake.js';
import type {
  AiConsented,
  CoachAgent,
  CoachCatalogStore,
  CoachFeedback,
  CoachGifting,
  CoachHiringStore,
  CoachLetterStore,
  CoachMemberFacts,
  CoachStreaks,
  CoachMemes,
  CoachWeather,
  WeatherWords,
  CoachOccasions,
  CoachPhotoUrls,
  CoachSettingsStore,
  CoachStores,
  CoachTimeZones,
  CoachEndedSquads,
  CoachTransaction,
  CoachUsage,
  SquadWeekSource,
} from '../ports.js';
import { challengeTool, toolbox, type WakeDraft } from './coach-wakes/toolbox.js';
import { mondayOf, wallClockAt } from '@wildcard/time-zones';

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

/** The file a squad's coach starts from: its name. */
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
   * Has the squad's coach, if it has one, welcome a member who just joined it, now (Tracy,
   * 2026-11-12): queues the member's welcome and runs the squad's waiting wakes. Does nothing
   * while coaching is off. What doesn't finish now, the next `run` does.
   */
  welcome(input: { readonly squad: SquadId; readonly member: string }): Promise<void>;
  /**
   * For testing a prompt (Tracy, 2026-11-08): runs today's daily wake of the member's squad now,
   * for that member alone, and says what the coach would write and give, saving and sending
   * nothing; only its tokens are recorded, against the squad's caps, which it keeps to like any
   * wake. Works while coaching is off too. With `deliver` (Tracy, 2026-11-09: 要让他真的发给我自己)
   * the member's note, with its challenge, is saved as a real note of today, every time it is
   * asked, so it reaches their phone and coach page like the morning one, and the newest is the
   * day's; the 战术板 line and the gift stay a preview, since the board is the squad's and a gift
   * is one a week.
   */
  preview(input: {
    readonly squad: SquadId;
    readonly member: string;
    readonly deliver?: boolean;
  }): Promise<CoachPreview>;
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
      /**
       * Asked to deliver: whether the note was saved for the member. False when the coach wrote
       * none, or the run failed.
       */
      readonly delivered?: boolean;
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
  /** Counts each run to its squad and member, and says when the squad's AI budget is spent. */
  readonly usage: CoachUsage;
  readonly transaction: CoachTransaction;
  readonly agent: CoachAgent;
  readonly squadWeek: SquadWeekSource;
  readonly aiConsented: AiConsented;
  readonly hiring: CoachHiringStore;
  /** The change of coach that brought the coach now and the letter left with it, if any. */
  readonly letters: Pick<CoachLetterStore, 'handover' | 'ofHandover'>;
  readonly clock: () => Date;
  readonly photoUrls: CoachPhotoUrls;
  /** Member stats and plans the coach looks up. */
  readonly memberFacts: CoachMemberFacts;
  /** The streaks a 请假条 kept going, which its wake tells as a fact. */
  readonly streaks: CoachStreaks;
  /** The clock of each squad's daily wake and of the day it tells the coach. */
  readonly timeZonesAt: CoachTimeZones;
  /** Squads everyone left, which the coach never wakes for, whoever is hired there. */
  readonly ended: CoachEndedSquads;
  /** The meme library the coach draws humour from. */
  readonly memes: CoachMemes;
  readonly weatherOf: CoachWeather;
  /** The holidays and other moments on a day, beyond the coach's own calendar. */
  readonly occasions: CoachOccasions;
  /** Told each reply to a check-in once it is saved; the server tells its author. */
  readonly replied: CoachReplied;
  /** Told each answer to a member's reply once it is saved; the server tells that member. */
  readonly answered: CoachAnswered;
  /** Told each welcome once it is saved, delivered already; the server tells the new member. */
  readonly welcomed: CoachWelcomed;
  /** Of these members, the ones who keep the coach's messages on: only they get a morning note. */
  readonly wantNotes: (members: readonly string[]) => Promise<readonly string[]>;
  readonly gifting: CoachGifting;
  /** Passes on to the team what a member asked of the app, filed as feedback from them. */
  readonly relayFeedback: CoachFeedback;
  /**
   * Whether coaches pass feedback on that day: off until the privacy policy's notice of it runs
   * out (the switch `coachFeedbackRelay`, Tracy 2026-11-12).
   */
  readonly relayingOn: (day: string) => Promise<boolean>;
  /** Told what went wrong after a wake's save, such as a gift that couldn't be given. */
  readonly warn: (message: string, details: Record<string, unknown>) => void;
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

/** A welcome the coach just saved for a member who joined its squad: a note only they read. */
export type CoachWelcomed = (welcome: {
  readonly squad: SquadId;
  readonly member: string;
  readonly coach: CoachId;
  readonly note: number;
  readonly day: string;
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
      // A squad that ended keeps its coach on record, but nothing runs for it.
      const ended = await deps.ended([...hired.keys()]);
      const squads = [...hired.keys()].filter((squad) => !ended.has(squad));
      let queued = 0;
      const zones = await deps.timeZonesAt(squads, now);
      for (const squad of squads) {
        const timeZone = zones(squad);
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

    welcome: async ({ squad, member }) => {
      const now = deps.clock();
      const settings = await deps.settings.current();
      if (!settings.coaching) return;
      const hired = await deps.hiring.hired();
      if (!hired.has(squad)) return;
      // The day on the squad's clock, as its daily wake counts days.
      const { day } = wallClockAt(now, (await deps.timeZonesAt([squad], now))(squad));
      await deps.stores.wakes.enqueue([{ squad, reason: { kind: 'joined', member, day } }], now);
      const coaches = new Map((await deps.catalog.list()).map((each) => [each.id, each]));
      await drain(deps, { squads: [squad], hired, coaches, settings, now });
    },

    preview: async (input) => previewDaily(deps, input),
  };
}

async function previewDaily(
  deps: CoachWakesDependencies,
  {
    squad,
    member,
    deliver = false,
  }: { readonly squad: SquadId; readonly member: string; readonly deliver?: boolean },
): Promise<CoachPreview> {
  const now = deps.clock();
  const settings = await deps.settings.current();
  const hiredCoach = (await deps.hiring.hired()).get(squad);
  const coach = (await deps.catalog.list()).find(({ id }) => id === hiredCoach);
  if (coach === undefined) return { ran: false, why: 'the squad has no coach' };
  const offDuty = await deps.usage.offDutyWhy({ squad, model: settings.model });
  if (offDuty !== undefined) return { ran: false, why: `off duty today: ${offDuty}` };
  const zone = (await deps.timeZonesAt([squad], now))(squad);
  const day = wallClockAt(now, zone).day;
  const week = await weekOf(deps, { squad, weekStart: mondayOf(day) });
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
  const { run, draft, roster, costMicros } = thought;
  const note = draft.memberNotes.get(member);
  const gift = draft.gifts.get(member);
  const reads = await noteReaders(deps, [member]);
  const delivered = deliver
    ? note !== undefined &&
      reads.length > 0 &&
      run.ok &&
      (await deps.stores.memberNotes.save({ squad, member, coach: coach.id, day, ...note })) !==
        undefined
    : undefined;
  const giftable = (
    await deps.gifting.options({ squad, members: await deps.aiConsented([member]) })
  ).open.has(member);
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
    ...(delivered === undefined ? {} : { delivered }),
    files: [...draft.changed].map((path) => ({
      path,
      body: shownBody(draft.files.get(path) ?? '', roster),
    })),
    steps: draft.steps,
    costMicros,
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
  // However a wake was queued (a check-in, a reply, a late retry), none runs once its squad ended.
  const ended = await deps.ended(squads);
  const live = squads.filter((squad) => !ended.has(squad));
  if (live.length === 0) return { done: 0, failed: 0 };
  let done = 0;
  let failed = 0;
  while (deps.clock().getTime() - now.getTime() < RUN_BUDGET_MS) {
    const wakes = await deps.stores.wakes.claim({
      squads: live,
      limit: AT_ONCE,
      now: deps.clock(),
    });
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
  if (reason.kind === 'daily' || reason.kind === 'dream' || reason.kind === 'joined') {
    return weekOf(deps, { squad: wake.squad, weekStart: mondayOf(reason.day) });
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
  /** The words of the member the wake answers there, which the coach may pass on to the team. */
  readonly heard: string | undefined;
  /** What the run cost, in US dollars' millionths. */
  readonly costMicros: number;
}

/**
 * Whether the squad's coach was its coach before, was fired and is back, and has not run for it
 * since it came back (a wake skipped without running, as for a check-in no longer shared with
 * AI, doesn't count).
 */
async function backAgain(deps: CoachWakesDependencies, squad: SquadId): Promise<boolean> {
  const since = await deps.hiring.hiredBackAt(squad);
  return since !== undefined && (await deps.usage.total({ squad, since })).wakes === 0;
}

/**
 * Whom the coach took over from on the squad's last change of coach (换教练), on which day, and
 * the letter the outgoing coach left the squad, so the new one can speak of it when asked (Tracy,
 * 2026-11-13). `undefined` for a coach hired with none before it.
 */
async function handoverOf(
  deps: CoachWakesDependencies,
  {
    squad,
    coach,
    week,
    zone,
  }: {
    readonly squad: SquadId;
    readonly coach: Coach;
    readonly week: SquadWeek;
    readonly zone: string;
  },
): Promise<TookOver | undefined> {
  const handover = await deps.letters.handover(squad);
  if (handover?.to !== coach.id) return undefined;
  const letter = await deps.letters.ofHandover(handover.hireEvent);
  return {
    from: (await coachNames(deps, week)).get(handover.from) ?? handover.from,
    day: wallClockAt(handover.at, zone).day,
    ...(letter === undefined ? {} : { letter: letter.text }),
  };
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
  // A welcome goes only to a member still in the squad who agreed to AI use and keeps the
  // coach's messages on, as a morning note does.
  const joiner = wake.reason.kind === 'joined' ? wake.reason.member : undefined;
  const welcomes =
    joiner !== undefined && week.members.some(({ member }) => member === joiner)
      ? await noteReaders(deps, [joiner])
      : [];
  if (joiner !== undefined && welcomes.length === 0) return undefined;
  const roster = rosterOf(week);
  // The files as the model reads them, by stored path, with members by their names now.
  const stored = new Map(
    [...(await deps.stores.memory.files(wake.squad))].map(([path, body]) => [
      path,
      shownBody(body, roster),
    ]),
  );
  // The squad's own clock: the day the wake is for, and the times the coach reads.
  const zone = (await deps.timeZonesAt([wake.squad], now))(wake.squad);
  const thread = await threadOf(deps, { wake, week, coach, now, zone });
  // A reply's wake with nothing to answer: the reply went, or isn't to this squad's coach.
  if (wake.reason.kind === 'comment' && thread === undefined) return undefined;
  const draft: WakeDraft = {
    files: new Map(stored),
    changed: new Set(),
    note: undefined,
    memberNotes: new Map(),
    challenges: new Map(),
    gifts: new Map(),
    reply: undefined,
    replyMentions: [],
    reaction: undefined,
    answer: undefined,
    answerMentions: [],
    challengeDone: false,
    feedback: undefined,
    steps: [],
  };
  // A squad whose coach hasn't written its file yet starts from its name,
  // saved with the run's other changes.
  if ((stored.get(SEEDED) ?? '') === '') {
    draft.files.set(SEEDED, squadSeed(week));
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
    : welcomes;
  // Whose pages the wake reads: everyone's on the squad's own wakes (the day's, the dream, a
  // welcome), else only the people under the check-in, so a line to one never brings up
  // another's things (Tracy, 2026-11-12).
  const about = aboutWhom(week, wake.reason);
  const files = new Map(
    shownPaths({ roster, coach: coach.id }).flatMap((path) => {
      const at = storedPathOf(path, { roster, coach: coach.id });
      const member = at === undefined ? undefined : memberOfPath(at);
      if (about !== undefined && member !== undefined && !about.has(member)) return [];
      return [[path, at === undefined ? undefined : draft.files.get(at)] as const];
    }),
  );
  // The day the wake is for: its own, or the squad's today on its own clock.
  const day = 'day' in wake.reason ? wake.reason.day : wallClockAt(now, zone).day;
  // Who may get a gift today: members who agreed to AI use and got none this week.
  const gifting = daily
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
  const heard = heardOf(week, wake.reason);
  const challenge =
    wake.reason.kind === 'checkIn' && author !== undefined
      ? await deps.stores.memberNotes.challengeOf({ squad: wake.squad, member: author, day })
      : undefined;
  // A 请假条 keeps its author's streaks going (Tracy, 2026-11-13): the coach is told how long.
  const { reason } = wake;
  const leave =
    reason.kind === 'checkIn' ? week.checkIns.find(({ id }) => id === reason.checkIn) : undefined;
  const keptStreaks =
    leave?.kind === 'disclaimer'
      ? await deps.streaks({ squad: wake.squad, member: leave.member })
      : undefined;
  const facts = {
    reason: wake.reason,
    week,
    files,
    // The holidays from the coach's calendar, then the app's own moments (a store open).
    occasions: [
      ...new Set([...holidaysOn(settings.holidays, day), ...(await deps.occasions(day))]),
    ],
    backAgain: await backAgain(deps, wake.squad),
    ...(wake.reason.kind === 'dream'
      ? {}
      : { handover: await handoverOf(deps, { squad: wake.squad, coach, week, zone }) }),
    recentNotes: daily
      ? await deps.stores.notes.recent({ squad: wake.squad, coach: coach.id, limit: RECENT_NOTES })
      : [],
    ...(thread === undefined ? {} : { thread: thread.thread }),
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
    ...(keptStreaks === undefined ? {} : { keptStreaks }),
    recentEmoji:
      wake.reason.kind === 'checkIn'
        ? await deps.stores.replies.recent({
            squad: wake.squad,
            coach: coach.id,
            limit: RECENT_EMOJI,
          })
        : [],
    talks: looksBack ? await talksOf(deps, { squad: wake.squad, week, coach, now }) : [],
    ...(wake.reason.kind === 'daily' || wake.reason.kind === 'joined'
      ? {
          noteTo: await briefsOf(deps, {
            // A member just joined: what they did before, since the coach knows nothing of them.
            record: wake.reason.kind === 'joined',
            squad: wake.squad,
            week,
            roster,
            members: noteTo,
            day,
          }),
        }
      : {}),
    ...(looksBack ? { yesterday: await yesterdayOf(deps, { squad: wake.squad, week, day }) } : {}),
  };
  // On a daily wake, the day's challenges are set first, by a run of their own on the settings'
  // challenge model, from the same task; the coach then writes its notes around them (Tracy,
  // 2026-11-12).
  const setting = daily && noteTo.length > 0;
  let settingCost = 0;
  if (setting) {
    const pickTask = taskOf(facts);
    if (pickTask === undefined) return undefined;
    settingCost = await setChallenges(deps, {
      wake,
      settings,
      roster,
      noteTo,
      draft,
      task: pickTask,
      author,
    });
  }
  const task = taskOf({ ...facts, ...(setting ? { setChallenges: draft.challenges } : {}) });
  if (task === undefined) return undefined;
  const run = await deps.agent.run({
    model: settings.model,
    reasoning: settings.reasoning,
    // It goes by its name in the squad's language (Tracy, 2026-11-08: Poki in English).
    instructions: instructionsOf(settings, coachIn(coach, week.language ?? 'zh-Hans')),
    task,
    tools: toolbox({
      week,
      roster,
      coach: coach.id,
      draft,
      kind: wake.reason.kind,
      to: author,
      // Only for a post made today: one from before midnight didn't do today's challenge.
      openChallenge:
        challenge !== undefined &&
        challengeOpen(challenge) &&
        postedOn({ week, reason: wake.reason, day, zone }),
      relaying: heard !== undefined ? 'heard' : 'nothing',
      ...((wake.reason.kind === 'checkIn' || wake.reason.kind === 'comment') &&
      !(await deps.relayingOn(day))
        ? { relaying: 'off' as const }
        : {}),
      ...photosOf(deps.photoUrls, { week, wake }),
      ...factsFor(deps, { squad: wake.squad, week, roster }),
      memes: deps.memes,
      noteTo,
      ...(gifting === undefined ? {} : { gifting }),
      pastWeek: (weeksAgo) =>
        weekOf(deps, {
          squad: wake.squad,
          weekStart: mondayOf(dayBefore(week.weekStart, weeksAgo * 7)),
        }),
      commentsOf: async (checkIn) => {
        const [reply, answers, names] = await Promise.all([
          deps.stores.replies.find(wake.squad, checkIn.id),
          deps.stores.answers.ofCheckIn(wake.squad, checkIn.id),
          coachNames(deps, week),
        ]);
        return saidLines(
          saidOf({ comments: checkIn.comments, reply, answers, names, coach: coach.id, zone }),
          roster,
        );
      },
    }),
    // Every wake of a coach begins with its same instructions, then its tools (each kind's own
    // last: the daily wake's post_note, a check-in's reply and react, a reply's answer), so
    // every kind shares the rest.
    cacheKey: `coach:${coach.id}`,
  });
  // The tokens were spent whatever comes next, so they are counted first, on their own: to the
  // member whose check-in or reply the wake answers, else to the squad alone. A run with no
  // wake is an admin's preview.
  const cost = await deps.usage.record({
    squad: wake.squad,
    ...(author === undefined ? {} : { member: author }),
    kind: wake.id === undefined ? 'preview' : 'wake',
    model: settings.model,
    usage: run.usage,
  });
  return {
    run,
    draft,
    stored,
    roster,
    thread,
    author,
    challenge,
    day,
    heard,
    costMicros: settingCost + cost,
  };
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
    const offDuty = await deps.usage.offDutyWhy({ squad: wake.squad, model: settings.model });
    if (offDuty !== undefined) {
      await deps.stores.wakes.skip(wake.id, `off duty: ${offDuty}`);
      return true;
    }
    const thought = await think(deps, { wake, settings, coach, now });
    if (thought === undefined) {
      await deps.stores.wakes.finish(wake.id);
      return true;
    }
    const { run, draft, stored, roster, thread, author, challenge, day, heard } = thought;
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
    const { reply, answer, welcome } = saved;
    if (welcome !== undefined) await deps.welcomed(welcome).catch(() => undefined);
    if (reply !== undefined && author !== undefined) {
      await deps.replied({ ...reply, author }).catch(() => undefined);
    }
    if (answer !== undefined && thread !== undefined) {
      await deps.answered({ ...answer, commenter: thread.commenter }).catch(() => undefined);
    }
    // What a member asked of the app is the feedback module's, filed after the run's save.
    const { reason } = wake;
    if (
      draft.feedback !== undefined &&
      author !== undefined &&
      heard !== undefined &&
      (reason.kind === 'checkIn' || reason.kind === 'comment')
    ) {
      const refused = await deps
        .relayFeedback({
          wake: wake.id,
          squad: wake.squad,
          coach: coach.id,
          member: author,
          checkIn: reason.checkIn,
          ...(reason.kind === 'comment' ? { comment: reason.comment } : {}),
          ...draft.feedback,
          quote: heard,
        })
        .catch((error: unknown) => (error instanceof Error ? error.message : String(error)));
      if (refused !== undefined) {
        deps.warn('coach feedback not passed on', { squad: wake.squad, member: author, refused });
      }
    }
    // Gifts are the unlocks module's, given after the run's save; one refused is only noted.
    for (const [member, { piece, line }] of draft.gifts) {
      const refused = await deps.gifting
        .give({ squad: wake.squad, member, coach: coach.id, piece, line })
        .catch((error: unknown) => (error instanceof Error ? error.message : String(error)));
      if (refused !== undefined) {
        deps.warn('coach gift not given', { squad: wake.squad, member, piece, refused });
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
): { readonly facts: () => Promise<string> } {
  const { memberFacts } = deps;
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
 * What the daily wake tells the coach about each member it writes a morning note to: this week's
 * whole plan and 饮食小目标, what they posted to the squad so far and how many days they trained,
 * so it needn't look them up. Without the plans (no `memberFacts`, or they can't be read), only
 * the posts and days trained.
 */
async function briefsOf(
  deps: CoachWakesDependencies,
  {
    squad,
    week,
    roster,
    members,
    day,
    record = false,
  }: {
    readonly record?: boolean;
    readonly squad: string;
    readonly week: SquadWeek;
    readonly roster: ReadonlyMap<string, string>;
    readonly members: readonly string[];
    readonly day: string;
  },
): Promise<readonly NoteBrief[]> {
  const facts =
    members.length === 0
      ? []
      : await deps.memberFacts({ squad, members, weekStart: week.weekStart }).catch(() => []);
  // The weather is a nice-to-have: a morning note goes out without it.
  const weather =
    members.length === 0
      ? new Map<string, WeatherWords>()
      : await deps.weatherOf({ members, day }).catch(() => new Map<string, WeatherWords>());
  return members.flatMap((member): NoteBrief[] => {
    const name = roster.get(member);
    if (name === undefined) return [];
    const trainedDays = new Set(
      week.checkIns
        .filter((each) => each.member === member && each.kind === 'trained')
        .map((each) => each.day),
    ).size;
    const mine = facts.find((each) => each.member === member);
    const posts = week.checkIns
      .filter((each) => each.member === member && each.day <= day)
      .toSorted(
        (a, b) => a.day.localeCompare(b.day) || a.createdAt.getTime() - b.createdAt.getTime(),
      )
      .map((each) => ({ day: each.day, what: postWhat(each) }));
    const nickname = week.members.find((each) => each.member === member)?.nickname;
    return [
      {
        name,
        ...(nickname === undefined ? {} : { nickname }),
        ...(record && mine !== undefined
          ? {
              record: {
                trainedDays: mine.trainedDays,
                ...(mine.topSport === undefined ? {} : { topSport: mine.topSport }),
              },
            }
          : {}),
        language: languageOf(week, member),
        trainedDays,
        posts,
        ...(weather.has(member) ? { weather: weather.get(member) } : {}),
        ...(mine === undefined || mine.plan.length === 0
          ? {}
          : { plan: { week: mine.plan, fuelGoals: mine.fuelGoals } }),
      },
    ];
  });
}

/**
 * Sets each member's challenge for the day into the draft, by a run of its own: the shared rules
 * and the settings' `challengeRules`, on the challenge model, or on the coach's own while that
 * one has no price to count it at. Its tokens are counted to the squad like the wake's.
 */
async function setChallenges(
  deps: CoachWakesDependencies,
  {
    wake,
    settings,
    roster,
    noteTo,
    draft,
    task,
    author,
  }: {
    readonly wake: Thought;
    readonly settings: CoachSettings;
    readonly roster: ReadonlyMap<string, string>;
    readonly noteTo: readonly string[];
    readonly draft: WakeDraft;
    readonly task: string;
    readonly author: string | undefined;
  },
): Promise<number> {
  const model =
    (await deps.usage.offDutyWhy({ squad: wake.squad, model: settings.challengeModel })) ===
    undefined
      ? settings.challengeModel
      : settings.model;
  const run = await deps.agent.run({
    model,
    reasoning: settings.reasoning,
    instructions: `${settings.rules}\n\n${settings.challengeRules}`,
    task,
    tools: [challengeTool(draft, { roster, noteTo })],
    cacheKey: 'coach:challenges',
  });
  return deps.usage.record({
    squad: wake.squad,
    ...(author === undefined ? {} : { member: author }),
    kind: wake.id === undefined ? 'preview' : 'wake',
    model,
    usage: run.usage,
  });
}

/** How many days of challenges the daily and dream wakes see, up to the day before. */
const CHALLENGE_DAYS = 7;

/** The squad's posts of the day before `day`: made for it, or posted on it. */
async function yesterdayOf(
  deps: CoachWakesDependencies,
  { squad, week, day }: { readonly squad: SquadId; readonly week: SquadWeek; readonly day: string },
): Promise<YesterdayFacts> {
  const yesterday = dayBefore(day, 1);
  // On a Monday, yesterday was last week.
  const weekStart = mondayOf(yesterday);
  const its = weekStart === week.weekStart ? week : await weekOf(deps, { squad, weekStart });
  // The last week's challenges, oldest first, and what each member said to them, why they let one
  // go included, only for members who still agree to AI use: seeing what it gave before, the coach
  // sets something else (Tracy, 2026-11-12).
  const days = Array.from({ length: CHALLENGE_DAYS }, (_, back) =>
    dayBefore(day, CHALLENGE_DAYS - back),
  );
  const set = (
    await Promise.all(
      days.map((each) => deps.stores.memberNotes.challengesOn({ squad, day: each })),
    )
  ).flat();
  const consented = new Set(await deps.aiConsented([...new Set(set.map(({ member }) => member))]));
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

/** A moment on the squad's clock, as the coach reads it: `11-09 周一 22:44`. */
function clockWords(moment: Date, zone: string): string {
  const { day, hour, minute } = wallClockAt(moment, zone);
  return `${dayWords(day)} ${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

/** `YYYY-MM-DD`, `days` before `day`. */
function dayBefore(day: string, days: number): string {
  return new Date(Date.parse(`${day}T00:00:00Z`) - days * 86_400_000).toISOString().slice(0, 10);
}

/** The photos of the check-in a wake is about, to look at on demand, when it has any. */
function photosOf(
  photoUrls: CoachPhotoUrls,
  { week, wake }: { readonly week: SquadWeek; readonly wake: NewWake },
): { readonly photos?: () => Promise<readonly string[]> } {
  if (wake.reason.kind !== 'checkIn' && wake.reason.kind !== 'comment') return {};
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
  readonly welcome?: Parameters<CoachWelcomed>[0];
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
  if (wake.reason.kind === 'joined') {
    const { member, day } = wake.reason;
    const note = draft.memberNotes.get(member);
    if (note === undefined) return {};
    // Delivered as it is saved: the member just joined, so it reaches them now, not the next
    // morning.
    const id = await stores.memberNotes.save({
      squad,
      member,
      coach: coach.id,
      day,
      text: note.text,
      wake: wake.id,
      deliveredNow: true,
    });
    return id === undefined
      ? {}
      : { welcome: { squad, member, coach: coach.id, note: id, day, text: note.text } };
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
    weekStart: mondayOf(dayBefore(week.weekStart, 7)),
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
      said: lately.flatMap(({ id, member, text, toCoach, mentionsCoach, replyTo, mentions }) => {
        const answer = answers.get(id);
        return [
          {
            member,
            text,
            to: {
              ...(toCoach === undefined ? {} : { toCoach }),
              ...(mentionsCoach === undefined ? {} : { mentionsCoach }),
              ...(replyTo === undefined ? {} : { replyTo }),
              ...(mentions === undefined ? {} : { mentions }),
            },
          },
          ...(answer === undefined ? [] : [{ member: undefined, text: answer }]),
        ];
      }),
    });
  }
  return talks;
}

/**
 * On a comment's wake (a reply to the coach or an @ of it), the whole comment section under its
 * check-in for the coach to go on, up to the one to answer: every member's comment and every
 * coach's reply and answers, this one's and a coach's before it; with who wrote that. `undefined` on another wake, or
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
    now,
    zone,
  }: {
    readonly wake: NewWake;
    readonly week: SquadWeek;
    readonly coach: Coach;
    readonly now: Date;
    readonly zone: string;
  },
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
  const answers = await deps.stores.answers.ofCheckIn(wake.squad, reason.checkIn);
  if (answers.some(({ comment }) => comment === reason.comment)) return undefined;
  // A reply to the coach needs something it said here, its reply to the check-in or an answer
  // to someone who wrote to it; an @ doesn't.
  const toThisCoach = new Set(
    comments.filter((each) => saidTo(each) === coach.id).map(({ id }) => id),
  );
  const answered = answers.some(({ comment }) => toThisCoach.has(comment));
  if (answering.toCoach !== undefined && reply === undefined && !answered) return undefined;
  const said = saidOf({
    comments: comments.filter((each) => each.at <= answering.at),
    reply: found,
    answers,
    names: await coachNames(deps, week),
    coach: coach.id,
    zone,
    answering: answering.id,
  });
  // Without the time now and each comment's, the coach takes an old @ for one just written.
  return { thread: { now: clockWords(now, zone), said }, commenter: answering.member };
}

/** Every coach's name in the squad's language, as members read them, by id. */
async function coachNames(
  deps: Pick<CoachWakesDependencies, 'catalog'>,
  week: Pick<SquadWeek, 'language'>,
): Promise<ReadonlyMap<string, string>> {
  const language = week.language ?? 'zh-Hans';
  return new Map(
    (await deps.catalog.list()).map((each) => [each.id, coachIn(each, language).name]),
  );
}

/**
 * What was said under a check-in, as the app shows it: the coach's reply to it first, then each
 * member's comment with the coach's answer to it right after it.
 */
function saidOf({
  comments,
  reply,
  answers,
  names,
  coach,
  zone,
  answering,
}: {
  readonly comments: readonly WeekComment[];
  readonly reply: { readonly coach: string; readonly text: string | undefined } | undefined;
  readonly answers: readonly {
    readonly comment: string;
    readonly coach: string;
    readonly text: string;
  }[];
  readonly names: ReadonlyMap<string, string>;
  /** The coach at work, by id: it reads itself as 你. */
  readonly coach: string;
  readonly zone: string;
  /** The comment the wake answers, if any. */
  readonly answering?: string;
}): CoachThread['said'] {
  const nameOf = (id: string): string => (id === coach ? '你' : (names.get(id) ?? '教练'));
  const by = (id: string): CoachThread['said'][number]['by'] =>
    id === coach ? 'you' : { coach: names.get(id) ?? '教练' };
  const answersOf = new Map(answers.map((each) => [each.comment, each]));
  const replied = reply?.text === undefined ? [] : [{ by: by(reply.coach), text: reply.text }];
  return [
    ...replied,
    ...comments.flatMap((comment) => {
      const to = comment.toCoach ?? comment.mentionsCoach;
      const answer = answersOf.get(comment.id);
      return [
        {
          by: { member: comment.member },
          text: comment.text,
          when: clockWords(comment.at, zone),
          ...(to === undefined
            ? {}
            : {
                to: {
                  kind: comment.toCoach === undefined ? ('mention' as const) : ('reply' as const),
                  coach: nameOf(to),
                },
              }),
          ...(comment.replyTo === undefined ? {} : { replyTo: comment.replyTo }),
          ...(comment.mentions === undefined ? {} : { mentions: comment.mentions }),
          ...(comment.id === answering ? { answering: true } : {}),
        },
        ...(answer === undefined ? [] : [{ by: by(answer.coach), text: answer.text }]),
      ];
    }),
  ];
}

/** The members a daily wake writes a morning note to. */
async function noteReaders(
  deps: Pick<CoachWakesDependencies, 'aiConsented' | 'wantNotes'>,
  members: readonly string[],
): Promise<readonly string[]> {
  const consented = await deps.aiConsented(members);
  return deps.wantNotes(consented);
}

/**
 * What the member a check-in's or reply's wake answers said under that post, in their own words:
 * the post's line, if it is theirs, then their comments there up to the one the wake answers, so
 * what they asked is quoted with the yes that came after it. Undefined when they said nothing
 * there, or the post was only recorded.
 */
function heardOf(week: SquadWeek, reason: Wake['reason']): string | undefined {
  if (reason.kind !== 'checkIn' && reason.kind !== 'comment') return undefined;
  const checkIn = week.checkIns.find(({ id }) => id === reason.checkIn);
  if (checkIn === undefined || checkIn.unposted === true) return undefined;
  const member = addresseeOf(week, reason);
  const answering =
    reason.kind === 'comment'
      ? checkIn.comments.find(({ id }) => id === reason.comment)
      : undefined;
  const said = [
    ...(checkIn.member === member && checkIn.text !== undefined ? [checkIn.text] : []),
    ...(answering === undefined
      ? []
      : checkIn.comments
          .filter((each) => each.member === member && each.at <= answering.at)
          .map(({ text }) => text)),
  ].filter((words) => words.trim() !== '');
  return said.length === 0 ? undefined : said.join('\n');
}

/**
 * The members a check-in's or reply's wake is about, whose pages it reads: the check-in's author
 * and everyone who commented under it. Someone only @-ed there is left out; the model can still
 * write to their page by name. `undefined` for the squad's own wakes (the day's, the dream, a
 * welcome), which read every page.
 */
function aboutWhom(week: SquadWeek, reason: Wake['reason']): ReadonlySet<string> | undefined {
  if (reason.kind !== 'checkIn' && reason.kind !== 'comment') return undefined;
  const checkIn = week.checkIns.find(({ id }) => id === reason.checkIn);
  if (checkIn === undefined) return new Set();
  return new Set([checkIn.member, ...checkIn.comments.map(({ member }) => member)]);
}

/**
 * Whom a line on this wake is for: the check-in's author, the member who wrote to the coach, or
 * the member it welcomes.
 */
function addresseeOf(week: SquadWeek, reason: Wake['reason']): string | undefined {
  if (reason.kind === 'checkIn') {
    return week.checkIns.find(({ id }) => id === reason.checkIn)?.member;
  }
  if (reason.kind === 'comment') {
    return week.checkIns
      .find(({ id }) => id === reason.checkIn)
      ?.comments.find(({ id }) => id === reason.comment)?.member;
  }
  if (reason.kind === 'joined') return reason.member;
  return undefined;
}
