import { costMicros } from '@wildcard/ai-usage';
import {
  CoachEmoji,
  CoachId,
  createCoachWakes,
  SquadId,
  type CoachAgent,
  type CoachSettings,
  type CoachStores,
  type CoachWakesDependencies,
  type PlanDayFacts,
  type SquadWeek,
} from '@wildcard/coach';
import type { TokenUsage } from '@wildcard/language-model';

import type { EvalCase, EvalSettings } from './eval-case.js';

// Runs one case as the server would: the coach's own wake code (`createCoachWakes`), its task,
// tools and saving, over stores that hold the case in memory, with only the agent real. What the
// wake would have saved and told is kept as the trial's outcome; nothing leaves this process but
// the model's requests.
//
// Not yet held by a case, so told to the model empty: streaks, members' counts and 饮食小目标
// (only their plans are held), memes, weather and holidays, and the coach's hire date (the
// epoch). A case about one of them needs it added here first.

/** The squad every case runs in: cases name members and check-ins, never their squad. */
const SQUAD = SquadId.parse('00000000-0000-4000-8000-000000000001');

const NO_TOKENS: TokenUsage = {
  requests: 0,
  inputTokens: 0,
  cachedInputTokens: 0,
  outputTokens: 0,
};

/** One tool call of the run, as `coach_wake_steps` keeps it. */
export interface TrialStep {
  readonly tool: string;
  readonly input: unknown;
  readonly output: string;
}

/** What one run of the coach did on a case's wake. */
export interface TrialOutcome {
  /** Set when the run failed, or the wake didn't run at all. */
  readonly error?: string;
  /** Its line to the check-in, and its emoji. */
  readonly reply?: string;
  readonly emoji?: string;
  /** Its answer to the comment. */
  readonly answer?: string;
  /** The memory files it changed, as saved. */
  readonly files: readonly { readonly path: string; readonly body: string }[];
  /** What it passed on to the team. */
  readonly feedback?: string;
  readonly steps: readonly TrialStep[];
  readonly usage: TokenUsage;
  readonly costMicros: number;
}

/** What a trial runs with: the settings (with any change asked for) and the agent. */
export interface TrialSetup {
  readonly settings: EvalSettings;
  readonly agent: CoachAgent;
}

/** Runs the case's wake once and says what the coach did. */
export async function runTrial(
  testCase: EvalCase,
  { settings, agent }: TrialSetup,
): Promise<TrialOutcome> {
  const coach = CoachId.parse(testCase.coach);
  const coachSettings: CoachSettings = { ...settings.coach, coaching: true };
  const price = settings.prices[coachSettings.model];
  if (price === undefined) throw new Error(`No price for ${coachSettings.model} in the settings`);

  const steps: TrialStep[] = [];
  const files: { path: string; body: string }[] = [];
  let reply: { text: string | undefined; emoji: string | undefined } | undefined;
  let answer: string | undefined;
  let feedback: string | undefined;
  let usage: TokenUsage = { requests: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 0 };
  let queued: Parameters<CoachStores['wakes']['enqueue']>[0] = [];
  // What happened to the wake, which the stores and the agent below are told.
  const run: { failed: string | undefined; claimed: boolean; thought: boolean } = {
    failed: undefined,
    claimed: false,
    thought: false,
  };

  const weekAt = (weekStart: string): SquadWeek => {
    const found = [testCase.week, ...testCase.pastWeeks].find(
      (each) => each.weekStart === weekStart,
    );
    return found ?? { weekStart, members: testCase.week.members, checkIns: [] };
  };
  const challengeOf: CoachStores['memberNotes']['challengeOf'] = ({ member, day }) => {
    const index = testCase.challenges.findIndex(
      (each) => each.member === member && each.day === day,
    );
    const found = testCase.challenges[index];
    if (found === undefined) return Promise.resolve(undefined);
    return Promise.resolve({
      note: index + 1,
      day: found.day,
      challenge: found.challenge,
      coach: { id: coach, name: coach, look: coach },
      answer: found.answer,
      reason: found.reason,
      completion: found.completion,
    });
  };
  const nothing = () => Promise.resolve(undefined);

  const stores: CoachStores = {
    wakes: {
      enqueue: (wakes) => {
        queued = wakes;
        return Promise.resolve(wakes.length);
      },
      claim: () => {
        // The case's own wake, once: the day's, among those due then, for the challenges; any
        // other the code queues waits.
        if (run.claimed) return Promise.resolve([]);
        run.claimed = true;
        const own = queued.filter(
          ({ reason }) =>
            (testCase.wake.kind !== 'challenges' && testCase.wake.kind !== 'daily') ||
            reason.kind === 'daily',
        );
        return Promise.resolve(own.slice(0, 1).map((wake) => ({ ...wake, id: 1 })));
      },
      finish: () => Promise.resolve(),
      fail: (_wake, error) => {
        run.failed = error;
        return Promise.resolve();
      },
      skip: (_wake, why) => {
        run.failed = `skipped: ${why}`;
        return Promise.resolve();
      },
    },
    memory: {
      files: () => Promise.resolve(new Map(Object.entries(testCase.files))),
      save: ({ files: saved }) => {
        files.push(...saved);
        return Promise.resolve();
      },
    },
    notes: { save: () => Promise.resolve(true), recent: () => Promise.resolve([]) },
    memberNotes: {
      save: nothing,
      challengeOf,
      deliveredBetween: () => Promise.resolve([]),
      challengesOn: ({ day }) =>
        Promise.resolve(
          testCase.challenges
            .filter((each) => each.day === day)
            .map((each, index) => ({
              note: index + 1,
              day: each.day,
              challenge: each.challenge,
              coach: { id: coach, name: coach, look: coach },
              answer: each.answer,
              reason: each.reason,
              completion: each.completion,
              member: each.member,
            })),
        ),
    },
    replies: {
      save: ({ text, emoji }) => {
        reply = { text, emoji };
        return Promise.resolve(true);
      },
      find: (_squad, checkIn) => {
        const found = testCase.replies.find((each) => each.checkIn === checkIn);
        return Promise.resolve(
          found === undefined
            ? undefined
            : { coach: CoachId.parse(found.coach ?? coach), text: found.text },
        );
      },
      // This coach's own, newest first, as the store gives them.
      recent: () =>
        Promise.resolve(
          testCase.replies.toReversed().flatMap((each) => {
            const parsed = CoachEmoji.safeParse(each.emoji);
            return parsed.success && (each.coach ?? coach) === coach ? [parsed.data] : [];
          }),
        ),
    },
    answers: {
      save: ({ text }) => {
        answer = text;
        return Promise.resolve(true);
      },
      ofCheckIn: (_squad, checkIn) =>
        Promise.resolve(
          testCase.answers
            .filter((each) => each.checkIn === checkIn)
            .map((each) => ({
              comment: each.comment,
              coach: CoachId.parse(each.coach ?? coach),
              text: each.text,
              at: each.at,
            })),
        ),
    },
    steps: {
      record: ({ steps: recorded }) => {
        steps.push(...recorded);
        return Promise.resolve();
      },
    },
  };

  const everyone = () =>
    Promise.resolve([...new Set(testCase.week.members.map(({ member }) => member))]);
  const deps: CoachWakesDependencies = {
    settings: { current: () => Promise.resolve(coachSettings), save: () => Promise.resolve(false) },
    catalog: { list: () => Promise.resolve(settings.coaches), save: () => Promise.resolve(false) },
    stores,
    usage: {
      offDutyWhy: nothing,
      record: ({ usage: used }) => {
        usage = add(usage, used);
        return Promise.resolve(costMicros(used, price));
      },
      total: () =>
        Promise.resolve({
          wakes: 1,
          requests: 0,
          inputTokens: 0,
          cachedInputTokens: 0,
          outputTokens: 0,
          costMicros: 0,
        }),
    },
    transaction: (work) => work(stores),
    agent: {
      run: (request) => {
        // On the challenges' case only the run that sets them is the model's; the notes after
        // it are not written.
        if (
          testCase.wake.kind === 'challenges' &&
          !request.tools.some(({ name }) => name === 'set_challenge')
        ) {
          return Promise.resolve({ ok: true, usage: NO_TOKENS });
        }
        run.thought = true;
        return agent.run(request);
      },
    },
    squadWeek: ({ weekStart }) => Promise.resolve(weekAt(weekStart)),
    // A case holds only the words of members who agreed: whoever is in it agreed.
    aiConsented: (members) => Promise.resolve(members),
    hiring: {
      coachOf: () => Promise.resolve({ coach, since: new Date(0) }),
      hired: () => Promise.resolve(new Map([[SQUAD, coach]])),
      hiredBackAt: nothing,
      hire: () => Promise.resolve('hasCoach'),
      fire: nothing,
      replace: () => Promise.resolve('same'),
    },
    letters: {
      handover: () =>
        Promise.resolve(
          testCase.handover === undefined
            ? undefined
            : {
                hireEvent: 1,
                squad: SQUAD,
                from: CoachId.parse(testCase.handover.from),
                to: coach,
                at: testCase.handover.at,
              },
        ),
      ofHandover: () => {
        const handover = testCase.handover;
        if (handover?.letter === undefined) return Promise.resolve(undefined);
        const named = (id: string) => ({ id, name: id, look: id });
        return Promise.resolve({
          id: 1,
          squad: SQUAD,
          from: named(handover.from),
          to: named(coach),
          day: handover.at.toISOString().slice(0, 10),
          text: handover.letter,
          at: handover.at,
        });
      },
    },
    clock: () => testCase.now,
    // The model is told how many photos a post has; it never sees the case's pictures.
    photoUrls: () => Promise.resolve([]),
    memberFacts: ({ members }) =>
      Promise.resolve(
        members.flatMap((member) => {
          const plan = testCase.plans[member];
          return plan === undefined
            ? []
            : [
                {
                  member,
                  trainedDays: 0,
                  healthyMeals: 0,
                  cheatMeals: 0,
                  disclaimers: 0,
                  titles: 0,
                  plan: plan.map((day): PlanDayFacts =>
                    day === '休息'
                      ? { kind: 'rest' }
                      : day === '练'
                        ? { kind: 'train' }
                        : { kind: 'train', sport: day },
                  ),
                  fuelGoals: [],
                },
              ];
        }),
      ),
    streaks: () => Promise.resolve({}),
    timeZonesAt: () => Promise.resolve(() => testCase.timeZone),
    ended: () => Promise.resolve(new Set()),
    memes: () => Promise.resolve([]),
    weatherOf: () => Promise.resolve(new Map()),
    occasions: () => Promise.resolve([]),
    replied: () => Promise.resolve(),
    answered: () => Promise.resolve(),
    welcomed: () => Promise.resolve(),
    wantNotes: everyone,
    gifting: {
      options: () => Promise.resolve({ pool: [], open: new Map() }),
      given: () => Promise.resolve([]),
      give: nothing,
    },
    relayFeedback: ({ kind, text }) => {
      feedback = `${kind}: ${text}`;
      return Promise.resolve(undefined);
    },
    relayingOn: () => Promise.resolve(true),
    warn: () => undefined,
  };

  const wakes = createCoachWakes(deps);
  const { wake } = testCase;
  if (wake.kind === 'checkIn') {
    await wakes.checkedIn({ checkIn: wake.checkIn, squads: [SQUAD] });
  } else if (wake.kind === 'comment') {
    await wakes.answer({ checkIn: wake.checkIn, comment: wake.comment, coach, squads: [SQUAD] });
  } else {
    await wakes.run();
  }
  return {
    ...(run.failed !== undefined
      ? { error: run.failed }
      : run.thought
        ? {}
        : {
            error:
              "the coach did not run: the wake's check-in or comment is not in the case, or has nothing to answer",
          }),
    ...(reply?.text === undefined ? {} : { reply: reply.text }),
    ...(reply?.emoji === undefined ? {} : { emoji: reply.emoji }),
    ...(answer === undefined ? {} : { answer }),
    files,
    ...(feedback === undefined ? {} : { feedback }),
    steps,
    usage,
    costMicros: costMicros(usage, price),
  };
}

function add(a: TokenUsage, b: TokenUsage): TokenUsage {
  return {
    requests: a.requests + b.requests,
    inputTokens: a.inputTokens + b.inputTokens,
    cachedInputTokens: a.cachedInputTokens + b.cachedInputTokens,
    outputTokens: a.outputTokens + b.outputTokens,
  };
}
