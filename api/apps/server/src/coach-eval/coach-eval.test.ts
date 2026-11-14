import type { AgentRun, CoachAgent, CoachTool } from '@wildcard/coach';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { codeVerdict, inLanguage } from './checks.js';
import { EvalCase, EvalSettings, type Expectation } from './eval-case.js';
import { runTrial } from './harness.js';
import { reportOf, runEval } from './run-eval.js';

// The eval's harness runs the coach's own wake code; these drive it with a scripted agent that
// calls the tools the wake hands it, so no model is asked.

const TRACY = '11111111-1111-4111-8111-111111111111';
const FRAN = '22222222-2222-4222-8222-222222222222';

const settings = EvalSettings.parse({
  version: 1,
  coach: {
    version: 1,
    coaching: false,
    model: 'openai/gpt-6-luna',
    reasoning: 'low',
    dreamModel: 'openai/gpt-6-luna',
    dreamReasoning: 'high',
    rules: '规矩',
    wakes: '醒来',
    challengeModel: 'openai/gpt-6-luna',
    challengeRules: '挑战',
    noteHour: 8,
    holidays: [],
  },
  coaches: [
    {
      version: 3,
      id: 'alpaca',
      position: 1,
      tier: 'advanced',
      name: '驼驼',
      catchphrase: '呸，不是呸你',
      title: '戏精教练',
      background: '刚吹完头发',
      yearsCoaching: 3,
      experience: '委屈没断过',
      style: '戏精',
      tags: ['戏精'],
      pay: '别碰我头发',
      soul: '你是驼驼。',
      look: 'alpaca',
      offered: true,
    },
  ],
  prices: {
    'openai/gpt-6-luna': {
      inputMicrosPerMillion: 100_000,
      cachedInputMicrosPerMillion: 10_000,
      outputMicrosPerMillion: 500_000,
    },
  },
});

/** Tracy said she won't do the squats under one post, then posts a mall walk. */
const squats = EvalCase.parse({
  version: 1,
  id: 'squats-given-up',
  title: 'A walk after giving the squats up is not the squats done',
  coach: 'alpaca',
  now: '2026-11-14T04:31:00Z',
  timeZone: 'America/New_York',
  week: {
    weekStart: '2026-11-09',
    members: [
      { member: TRACY, nickname: 'Tracy' },
      { member: FRAN, nickname: 'Fran' },
    ],
    checkIns: [
      {
        id: 'basketball',
        member: TRACY,
        day: '2026-11-13',
        createdAt: '2026-11-14T02:16:00Z',
        kind: 'trained',
        sport: '篮球',
        minutes: 15,
        comments: [
          {
            id: 'oops',
            member: TRACY,
            text: 'oops不准备做了',
            at: '2026-11-14T02:30:00Z',
            toCoach: 'alpaca',
          },
        ],
      },
      {
        id: 'mall',
        member: TRACY,
        day: '2026-11-13',
        createdAt: '2026-11-14T04:30:00Z',
        kind: 'trained',
        sport: '快走',
        minutes: 20,
        text: '逛商场是我唯一的运动',
      },
    ],
  },
  replies: [{ checkIn: 'basketball', text: '深蹲 50 个还等你收尾呢', emoji: '👏' }],
  challenges: [
    {
      member: TRACY,
      day: '2026-11-13',
      challenge: { title: '做深蹲', amount: 50, unit: '个' },
      answer: 'accepted',
    },
  ],
  wake: { kind: 'checkIn', checkIn: 'mall' },
  expect: [
    { kind: 'tool', tool: 'complete_challenge', called: false },
    { kind: 'says' },
    { kind: 'avoids', words: ['稳'] },
  ],
});

/** An agent that calls the named tools with these arguments, in order, and stops. */
function scripted(calls: readonly (readonly [string, unknown])[]): CoachAgent & {
  readonly seen: { task: string; tools: readonly string[] };
} {
  const seen: { task: string; tools: readonly string[] } = { task: '', tools: [] };
  return {
    seen,
    run: async ({ task, tools }): Promise<AgentRun> => {
      seen.task = task;
      seen.tools = tools.map(({ name }) => name);
      const byName = new Map<string, CoachTool>(tools.map((each) => [each.name, each]));
      for (const [name, input] of calls) {
        const found = byName.get(name);
        if (found === undefined) return { ok: false, usage: usage(), error: `no tool ${name}` };
        await found.run(input);
      }
      return { ok: true, usage: usage() };
    },
  };
}

function usage() {
  return { requests: 1, inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 0 };
}

describe('the coach eval harness', () => {
  it('runs the real check-in wake: its task, its tools and what it saves', async () => {
    const agent = scripted([
      ['react', { emoji: '😂' }],
      ['reply', { text: '商场逛 20 分钟，腿也算动过了' }],
      ['complete_challenge', {}],
    ]);
    const outcome = await runTrial(squats, { settings, agent });

    expect(agent.seen.tools).toContain('complete_challenge');
    expect(agent.seen.task).toContain('逛商场是我唯一的运动');
    expect(agent.seen.task).toContain('做深蹲 50 个');
    expect(outcome).toMatchObject({
      reply: '商场逛 20 分钟，腿也算动过了',
      emoji: '😂',
      challengeDone: true,
      costMicros: 100_000,
    });
    expect(outcome.steps.map(({ tool }) => tool)).toEqual(['react', 'reply', 'complete_challenge']);
    expect(codeVerdict(expectation(0), outcome)).toEqual({
      pass: false,
      note: 'complete_challenge was called',
    });
    expect(codeVerdict(expectation(1), outcome)).toEqual({ pass: true });
  });

  it('answers a comment to the coach on its own wake', async () => {
    const commentCase = EvalCase.parse({
      ...squatsInput(),
      id: 'answer-oops',
      replies: [{ checkIn: 'basketball', text: '深蹲 50 个还等你收尾呢' }],
      wake: { kind: 'comment', checkIn: 'basketball', comment: 'oops' },
    });
    const agent = scripted([['answer', { text: '行，深蹲那页我撕了' }]]);
    const outcome = await runTrial(commentCase, { settings, agent });

    expect(agent.seen.task).toContain('oops不准备做了');
    expect(outcome.answer).toBe('行，深蹲那页我撕了');
    expect(outcome.error).toBeUndefined();
  });

  it('reports a wake that never ran as an error', async () => {
    const missing = EvalCase.parse({
      ...squatsInput(),
      wake: { kind: 'checkIn', checkIn: 'gone' },
    });
    const outcome = await runTrial(missing, { settings, agent: scripted([]) });
    expect(outcome.error).toMatch(/did not run/);
  });

  it('counts a case as passed only when every check holds, over each trial', async () => {
    const run = await runEval({
      cases: [squats],
      settings,
      agent: scripted([['reply', { text: '商场也是赛道' }]]),
      trials: 2,
    });
    expect(run.cases[0]?.trials.map(({ pass }) => pass)).toEqual([true, true]);
    expect(reportOf(run, { at: new Date('2026-11-14T06:00:00Z') })).toContain(
      '| squats-given-up | 2/2 |  |',
    );
  });

  it('tells Chinese lines from English ones', () => {
    expect(inLanguage('Ptooey. Not at you, Hannah!', 'en')).toBe(true);
    expect(inLanguage('毛毛雨里还去跑！', 'en')).toBe(false);
    expect(inLanguage('毛毛雨里还去跑！Central Park', 'zh-Hans')).toBe(true);
  });
});

/** The squats case as written, before parsing. */
function squatsInput(): Record<string, unknown> {
  return z.record(z.string(), z.unknown()).parse(JSON.parse(JSON.stringify(squats)));
}

/** The squats case's expectation at `index`. */
function expectation(index: number): Expectation {
  const found = squats.expect[index];
  if (found === undefined) throw new Error(`no expectation ${String(index)}`);
  return found;
}
