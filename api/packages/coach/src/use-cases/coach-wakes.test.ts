import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresCoachCatalog } from '../adapters/postgres-coach-catalog.js';
import { createPostgresCoachHiring } from '../adapters/postgres-coach-hiring.js';
import { createPostgresCoachLetters } from '../adapters/postgres-coach-letters.js';
import {
  createPostgresCoachSettings,
  type CoachTables,
} from '../adapters/postgres-coach-settings.js';
import {
  createPostgresCoachActivity,
  createPostgresCoachNoteDelivery,
  createPostgresCoachReport,
  createPostgresCoachStores,
} from '../adapters/postgres-coach-stores.js';
import { CoachId } from '../domain/coach.js';
import { CoachModel, MemberId, SquadId } from '../domain/settings.js';
import {
  CoachAlreadyHiredError,
  CoachChallengeDayOverError,
  CoachNoteNoChallengeError,
  CoachNoteNotFoundError,
  CoachNotOfferedError,
  CoachSquadNotFoundError,
  NoCoachHiredError,
} from '../errors.js';
import type { SquadWeek } from '../domain/squad-week.js';
import type {
  AgentRun,
  CoachAgent,
  CoachFeedback,
  CoachGifting,
  CoachHiringStore,
  CoachMemberFacts,
  CoachMemes,
  CoachPhotoUrls,
  CoachTool,
  CoachUsage,
  CoachWeather,
} from '../ports.js';
import { createCoachActivity } from './coach-activity.js';
import { createCoachNoteDelivery } from './coach-note-delivery.js';
import { createCoachReport } from './coach-report.js';
import { createCoachHiring } from './coach-hiring.js';
import { createCoachSettings } from './coach-settings.js';
import {
  createCoachWakes,
  type CoachAnswered,
  type CoachReplied,
  type CoachWakesDependencies,
  type CoachWelcomed,
} from './coach-wakes.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Each test works inside a
// transaction it rolls back, so the seeded settings stay as they are for the other tests.
const db = new Kysely<CoachTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

class RolledBack extends Error {}

/** What a wake's task tells a coach hired back, until it first runs for the squad again. */
const BACK_AGAIN = '你以前带过这个小队，被换掉后，现在又被请回来了。';

/** 10:00 in New York on a Sunday: past the daily wake's hour. */
const now = new Date('2026-11-01T15:00:00Z');

/** One run as the usage ledger counted it. */
type CountedRun = Parameters<CoachUsage['record']>[0] & {
  readonly at: Date;
  readonly costMicros: number;
};

/**
 * The AI usage ledger as the coach sees it, kept in memory (the ledger's own tests run it on
 * Postgres, prices and caps included): each run at $0.25 a million input tokens and $2 a million
 * output, and off duty while `offDuty` gives a reason.
 */
function countedUsage(offDuty: () => string | undefined = () => undefined) {
  const runs: CountedRun[] = [];
  const usage: CoachUsage = {
    offDutyWhy: () => Promise.resolve(offDuty()),
    record: (entry) => {
      const costMicros = Math.ceil(
        ((entry.usage.inputTokens - entry.usage.cachedInputTokens) * 250_000 +
          entry.usage.outputTokens * 2_000_000) /
          1_000_000,
      );
      runs.push({ ...entry, at: new Date(), costMicros });
      return Promise.resolve(costMicros);
    },
    total: ({ squad, since }) => {
      const counted = runs.filter((run) => run.squad === squad && run.at >= (since ?? run.at));
      const sum = (of: (run: CountedRun) => number) =>
        counted.reduce((total, run) => total + of(run), 0);
      return Promise.resolve({
        wakes: counted.length,
        requests: sum((run) => run.usage.requests),
        inputTokens: sum((run) => run.usage.inputTokens),
        cachedInputTokens: sum((run) => run.usage.cachedInputTokens),
        outputTokens: sum((run) => run.usage.outputTokens),
        costMicros: sum((run) => run.costMicros),
      });
    },
  };
  return { usage, runs };
}

interface Fixture {
  readonly trx: Kysely<CoachTables>;
  /** What the fixture's coach ran, as the usage ledger counted it. */
  readonly counted: ReturnType<typeof countedUsage>;
  readonly squad: SquadId;
  readonly mia: string;
  readonly leo: string;
  readonly checkIn: string;
  readonly week: SquadWeek;
}

/** A squad of two that hired 小混, with one check-in made 10 minutes ago, and coaching on. */
async function rolledBack(test: (fixture: Fixture) => Promise<void>) {
  // The test's own failure, not the rollback, when it has one.
  await db
    .transaction()
    .execute(async (trx) => {
      const [mia, leo, squadId, checkIn] = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
      // Only this squad has a coach here: squads other test files hired one for (and may leave
      // behind) would otherwise wake too, since the job looks at every squad with a coach.
      await sql`delete from public.squad_coaches`.execute(trx);
      for (const id of [mia, leo]) {
        await sql`insert into auth.users (id, email) values (${id}, ${`${id}@example.com`})`.execute(
          trx,
        );
      }
      await sql`insert into public.squads (id, name, invite_code) values (${squadId}, 'squad', ${squadId})`.execute(
        trx,
      );
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${checkIn}, ${mia}, '2026-11-01', ${new Date(now.getTime() - 10 * 60_000)}, 'trained',
          '{"version": 1, "sport": "run"}')`.execute(trx);
      // Route tests that ran before may have left squads with a coach; this run wakes only its own.
      await sql`delete from public.squad_coaches`.execute(trx);
      const squad = SquadId.parse(squadId);
      await createCoachSettings({ store: createPostgresCoachSettings(trx) }).change(
        { coaching: true },
        MemberId.parse(mia),
      );
      // A run wakes every squad with a coach: other test files' squads, committed while this
      // one runs, would count too.
      await sql`delete from public.squad_coaches`.execute(trx);
      await createCoachHiring({
        hiring: createPostgresCoachHiring(trx),
        catalog: createPostgresCoachCatalog(trx),
      }).hire({ squad, coach: CoachId.parse('xiaohun'), by: MemberId.parse(mia) });
      const week: SquadWeek = {
        weekStart: '2026-10-26',
        members: [{ member: mia, nickname: '米亚' }, { member: leo }],
        checkIns: [
          {
            id: checkIn,
            member: mia,
            day: '2026-11-01',
            createdAt: new Date(now.getTime() - 10 * 60_000),
            kind: 'trained',
            sport: '跑步',
            reactedBy: [],
            comments: [],
          },
        ],
      };
      await test({ trx, counted: countedUsage(), squad, mia, leo, checkIn, week });
      throw new RolledBack();
    })
    .catch((error: unknown) => {
      if (!(error instanceof RolledBack)) throw error;
    });
}

/** One step a scripted agent takes: a tool call, with what the tool answered checked. */
interface Step {
  readonly tool: string;
  readonly input: Record<string, unknown>;
}

/**
 * An agent that calls tools as a model would, by name and with JSON arguments, from a script
 * per task, and records every task and every answer.
 */
/** The day's challenge for 米亚 (米亚), as the run setting challenges sets it, by her name. */
const water = (): readonly Step[] => [
  {
    tool: 'set_challenge',
    input: {
      member: '米亚',
      recent: '这周练得少',
      needs: '补水',
      title: '喝水',
      amount: 8,
      unit: '杯',
      line: '天干',
    },
  },
];

/**
 * A model that runs the script's tool calls for each wake; the run setting the day's challenges
 * before a daily wake's notes runs `pick`'s instead and is kept in `picks`.
 */
function scriptedAgent(
  script: (task: string) => readonly Step[] | 'fail',
  pick: (task: string) => readonly Step[] = () => [],
) {
  const runs: {
    task: string;
    instructions: string;
    tools: string[];
    answers: string[];
    model: string;
    reasoning: string;
  }[] = [];
  const picks: typeof runs = [];
  const agent: CoachAgent = {
    async run({ instructions, task, tools, model, reasoning }): Promise<AgentRun> {
      const picking = tools.some(({ name }) => name === 'set_challenge');
      const steps = picking ? pick(task) : script(task);
      const usage = { requests: 2, inputTokens: 12_000, cachedInputTokens: 0, outputTokens: 800 };
      const answers: string[] = [];
      (picking ? picks : runs).push({
        task,
        instructions,
        tools: tools.map(({ name }) => name),
        answers,
        model,
        reasoning,
      });
      if (steps === 'fail') return { ok: false, usage, error: 'ModelBehaviorError: no' };
      for (const step of steps) {
        const tool: CoachTool | undefined = tools.find(({ name }) => name === step.tool);
        const answer = tool === undefined ? `no tool ${step.tool}` : await tool.run(step.input);
        answers.push(
          typeof answer === 'string' ? answer : [answer.text, ...answer.images].join(' '),
        );
      }
      return { ok: true, usage };
    },
  };
  return { agent, runs, picks };
}

/**
 * The coach at `at`, on the fixture's squad, whose week is `week` (else the fixture's, for
 * every week) and whose members all agreed to AI use unless `consented` says who did.
 */
function wakes(
  { trx, squad, week, counted }: Fixture,
  {
    agent,
    usage = counted.usage,
    at = now,
    weeks,
    consented,
    replied,
    answered,
    welcomed,
    photoUrls,
    memberFacts,
    wantNotes,
    memes,
    gifting,
    weatherOf,
    relayFeedback,
    relayingOn,
    ended,
  }: {
    readonly agent: CoachAgent;
    readonly usage?: CoachUsage;
    readonly at?: Date;
    readonly weeks?: Readonly<Record<string, SquadWeek>>;
    readonly consented?: readonly string[];
    readonly replied?: CoachReplied;
    readonly answered?: CoachAnswered;
    readonly welcomed?: CoachWelcomed;
    readonly photoUrls?: CoachPhotoUrls;
    readonly memberFacts?: CoachMemberFacts;
    readonly wantNotes?: (members: readonly string[]) => Promise<readonly string[]>;
    readonly memes?: CoachMemes;
    readonly gifting?: CoachGifting;
    readonly weatherOf?: CoachWeather;
    readonly relayFeedback?: CoachFeedback;
    readonly relayingOn?: (day: string) => Promise<boolean>;
    readonly ended?: boolean;
  },
) {
  const stores = createPostgresCoachStores(trx);
  return createCoachWakes({
    settings: createPostgresCoachSettings(trx),
    catalog: createPostgresCoachCatalog(trx),
    stores,
    usage,
    // Already in the test's transaction, which is rolled back at the end.
    transaction: (work) => work(stores),
    agent,
    squadWeek: ({ weekStart }) =>
      Promise.resolve(
        weeks === undefined
          ? week
          : (weeks[weekStart] ?? { weekStart, members: week.members, checkIns: [] }),
      ),
    aiConsented: (members) =>
      Promise.resolve(
        consented === undefined ? members : members.filter((member) => consented.includes(member)),
      ),
    hiring: ownSquadOnly(createPostgresCoachHiring(trx), squad),
    letters: createPostgresCoachLetters(trx),
    clock: () => at,
    ...quietPorts,
    ...(replied === undefined ? {} : { replied }),
    ...(answered === undefined ? {} : { answered }),
    ...(welcomed === undefined ? {} : { welcomed }),
    ...(photoUrls === undefined ? {} : { photoUrls }),
    ...(memberFacts === undefined ? {} : { memberFacts }),
    ...(wantNotes === undefined ? {} : { wantNotes }),
    ...(memes === undefined ? {} : { memes }),
    ...(gifting === undefined ? {} : { gifting }),
    ...(weatherOf === undefined ? {} : { weatherOf }),
    ...(relayFeedback === undefined ? {} : { relayFeedback }),
    ...(ended === true ? { ended: (squads) => Promise.resolve(new Set(squads)) } : {}),
    ...(relayingOn === undefined ? {} : { relayingOn }),
  });
}

/**
 * The ports a test doesn't look at: every squad on New York's clock, no facts, memes, weather,
 * occasions or gifts, every member wanting notes, photos at a test address.
 */
const quietPorts = {
  photoUrls: (paths) => Promise.resolve(paths.map((path) => `https://photos.test/${path}`)),
  memberFacts: () => Promise.resolve([]),
  streaks: () => Promise.resolve({}),
  timeZonesAt: () => Promise.resolve(() => 'America/New_York'),
  ended: () => Promise.resolve(new Set()),
  memes: () => Promise.resolve([]),
  weatherOf: () => Promise.resolve(new Map()),
  occasions: () => Promise.resolve([]),
  replied: () => Promise.resolve(),
  answered: () => Promise.resolve(),
  welcomed: () => Promise.resolve(),
  wantNotes: (members) => Promise.resolve(members),
  gifting: {
    options: () => Promise.resolve({ pool: [], open: new Map() }),
    given: () => Promise.resolve([]),
    give: () => Promise.resolve('no gifts in this test'),
  },
  relayFeedback: () => Promise.resolve('no feedback in this test'),
  relayingOn: () => Promise.resolve(true),
  warn: () => undefined,
} satisfies Partial<CoachWakesDependencies>;

/**
 * The hiring store, seeing only the fixture's squad among the squads with a coach: other
 * test files commit squads that keep theirs, and a run would wake those too.
 */
function ownSquadOnly(hiring: CoachHiringStore, squad: SquadId): CoachHiringStore {
  return {
    ...hiring,
    hired: async () =>
      new Map([...(await hiring.hired())].filter(([hiredSquad]) => hiredSquad === squad)),
  };
}

/** A comment under the fixture's check-in, as the check-ins module saves it. */
async function commentOn(
  { trx, checkIn }: Fixture,
  {
    member,
    text,
    at,
    toCoach,
    mentionsCoach,
  }: {
    readonly member: string;
    readonly text: string;
    readonly at: Date;
    readonly toCoach?: string;
    readonly mentionsCoach?: string;
  },
) {
  const id = randomUUID();
  await sql`insert into public.check_in_comments (id, check_in_id, member_id, text, reply_to_coach, mentions_coach, commented_at)
    values (${id}, ${checkIn}, ${member}, ${text}, ${toCoach ?? null}, ${mentionsCoach ?? null}, ${at})`.execute(
    trx,
  );
  return {
    id,
    member,
    text,
    at,
    ...(toCoach === undefined ? {} : { toCoach }),
    ...(mentionsCoach === undefined ? {} : { mentionsCoach }),
  };
}

describe('the coach', () => {
  it('does nothing while coaching is off', async () => {
    const { agent, runs } = scriptedAgent(() => []);
    const run = await createCoachWakes({
      settings: createPostgresCoachSettings(db),
      catalog: createPostgresCoachCatalog(db),
      stores: createPostgresCoachStores(db),
      usage: countedUsage().usage,
      transaction: () => Promise.reject(new Error('nothing to save')),
      agent,
      squadWeek: () => Promise.reject(new Error('no squad to read')),
      aiConsented: () => Promise.reject(new Error('no one to ask')),
      hiring: createPostgresCoachHiring(db),
      letters: createPostgresCoachLetters(db),
      clock: () => now,
      ...quietPorts,
    }).run();
    expect(run).toStrictEqual({ coaching: false, squads: 0, queued: 0, done: 0, failed: 0 });
    expect(runs).toHaveLength(0);
  });

  it('writes no morning note to a member who switched the coach off', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => [
        { tool: 'note_to', input: { member: '队员2', text: '今天走走' } },
      ]);
      const asked: (readonly string[])[] = [];
      const wantNotes = (members: readonly string[]) => {
        asked.push(members);
        return Promise.resolve(members.filter((member) => member !== fixture.leo));
      };

      await wakes(fixture, { agent, wantNotes }).run();

      const daily = runs.find(({ task }) => task.includes('新的一天'));
      expect(asked).toStrictEqual([[fixture.mia, fixture.leo]]);
      expect(daily?.task).toContain('## 今天的便条（下面每人各写一张）\n\n### 米亚\n');
      expect(daily?.task).not.toContain('### 队员2');
      expect(daily?.answers).toStrictEqual(['不能给 队员2 写便条；能写的是：米亚。']);
    });
  });

  it('wakes for a check-in and for the day, keeps its memory and its line, and counts tokens', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, leo } = fixture;
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('新的一天')
          ? [
              { tool: 'squad_week', input: {} },
              { tool: 'post_note', input: { text: '队员1 周日也跑了' } },
              { tool: 'post_note', input: { text: '  周日也跑了，米亚是认真的  ' } },
              { tool: 'note_to', input: { member: '米亚', text: '周日那趟我看见了' } },
              { tool: 'note_to', input: { member: '队员3', text: '你好' } },
              { tool: 'note_to', input: { member: '队员2', text: '队员2 今天动一动？' } },
              { tool: 'note_to', input: { member: '队员2', text: '今天动一动？走走也算' } },
              { tool: 'note_to', input: { member: '米亚', text: ' 周日那趟跑得真稳 ' } },
              {
                tool: 'edit_file',
                input: { path: 'people/队员2.md', find: '', replace: '还没打卡过' },
              },
              {
                tool: 'edit_file',
                input: { path: 'people/队员3.md', find: '', replace: '没这个人' },
              },
            ]
          : [
              { tool: 'remember', input: { path: 'memory.md', fact: ' 米亚 周日跑步 ' } },
              { tool: 'edit_file', input: { path: 'memory.md', find: '', replace: '没这个工具' } },
              { tool: 'post_note', input: { text: '不该有这个工具' } },
              { tool: 'reply', input: { point: '接住', text: '队员1 周日还跑' } },
              { tool: 'reply', input: { point: '接住', text: '跑'.repeat(101) } },
              { tool: 'reply', input: { point: '接住', text: '周日也跑？' } },
              { tool: 'reply', input: { point: '接住', text: '  周日也跑，腿还在吗  ' } },
              { tool: 'react', input: { emoji: '💩' } },
              { tool: 'react', input: { emoji: '🔥' } },
            ],
      );
      const told: Parameters<CoachReplied>[0][] = [];
      const replied: CoachReplied = (reply) => {
        told.push(reply);
        return Promise.resolve();
      };

      // The check-in, the night's dream (with nothing from yesterday to tidy) and the day.
      expect(await wakes(fixture, { agent, replied }).run()).toStrictEqual({
        coaching: true,
        squads: 1,
        queued: 3,
        done: 3,
        failed: 0,
      });
      // Told once, after the reply was saved, for the server to tell its author.
      expect(told).toStrictEqual([
        {
          squad,
          checkIn: fixture.checkIn,
          author: fixture.mia,
          coach: 'xiaohun',
          text: '周日也跑，腿还在吗',
          emoji: '🔥',
          mentions: [],
        },
      ]);

      // The check-in's wake ran first: it remembers, replies and reacts to the check-in, but
      // neither rewrites files nor posts on the 战术板; the daily wake posts but replies to nothing.
      expect(runs.map(({ tools }) => tools)).toStrictEqual([
        [
          'member_posts',
          'post_comments',
          'recall',
          'remember',
          'memes',
          'relay_feedback',
          'reply',
          'react',
        ],
        [
          'squad_week',
          'member_posts',
          'post_comments',
          'recall',
          'remember',
          'edit_file',
          'member_stats',
          'memes',
          'post_note',
          'note_to',
        ],
      ]);
      expect(runs[0]?.task).toContain('米亚 · 训练：跑步');
      expect(runs[0]?.answers).toStrictEqual([
        '记下了，在 memory.md。',
        'no tool edit_file',
        'no tool post_note',
        '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。',
        '太长了：101 字，最多 100 字。',
        '已回复。',
        '已换成这句。',
        expect.stringContaining('参数不对'),
        '已点 🔥。',
      ]);
      expect(runs[1]?.answers.slice(1)).toStrictEqual([
        '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。',
        '已写上战术板。',
        '便条写好了，给 米亚。',
        '不能给 队员3 写便条；能写的是：米亚、队员2。',
        '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。',
        '便条写好了，给 队员2。',
        '已换成这张，给 米亚。',
        '已改好，people/队员2.md 现在 5 字。',
        '没有 people/队员3.md 这个文件；能用的文件见任务里的列表。',
      ]);
      // Every member who agreed to AI use gets a note, whether or not they checked in.
      expect(runs[1]?.task).toContain(
        '## 今天的便条（下面每人各写一张）\n\n### 米亚\n- 这周练了：1 天\n- 这周发过：周日跑步\n- 用简体中文写。\n\n### 队员2\n- 这周练了：0 天\n- 这周发过：还没发过\n- 用简体中文写。',
      );
      // With yesterday's posts, here none.
      expect(runs[1]?.task).toContain('## 昨天（周六）小队的动态\n没人发动态。');
      expect(runs[0]?.task).not.toContain('便条');
      // The daily wake sees what the first one remembered, and the instructions are 小混's.
      expect(runs[1]?.task).toContain('### memory.md（你和大家之间的事）\n```\n- 米亚 周日跑步');
      expect(runs[1]?.task).toContain(
        '## 和你的对话（过去一天，打卡下面，先后顺序）\n没人在打卡下面和你说话。',
      );
      expect(runs[1]?.instructions).toContain('你是小混');
      expect(runs[1]?.instructions).toContain('不提谁没打卡');
      // How each wake goes is in the instructions, the same every time, so it can be cached.
      expect(runs[1]?.instructions).toContain('你会在四种时候醒来');
      // The seeded wakes let the coach pick its tools and say one thing per note, never "I remember".
      expect(runs[1]?.instructions).toContain('一张便条只说一件事');
      expect(runs[1]?.instructions).toContain('做什么、用哪个工具，你自己判断。');
      expect(runs[1]?.instructions).not.toContain('再加上记性里记着他的');
      // The 简历 is for the app only: the model never reads the coach's missing license.
      expect(runs[1]?.instructions).not.toContain('证还没考下来');
      // A reply reads only the coach's soul and the reply rules, never the other wakes'.
      expect(runs[0]?.instructions).toContain('你是小混');
      expect(runs[0]?.instructions).toContain('接住他这条最在意的那件事');
      expect(runs[0]?.instructions).not.toContain('你会在四种时候醒来');

      // A member's page is stored by their id, never by 队员N.
      const files = await sql<{ path: string; body: string; member_id: string | null }>`
        select path, body, member_id from public.coach_files where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(files.rows).toStrictEqual([
        // The first wake starts the squad's file; who is in it is in every task instead.
        {
          path: 'squad.md',
          body: '# 小队',
          member_id: null,
        },
        // Members named in a file are stored by id, so a name follows them when 队员N shifts.
        { path: 'memory.md', body: `- {队员:${fixture.mia}} 周日跑步`, member_id: null },
        { path: `people/${leo}.md`, body: '还没打卡过', member_id: leo },
      ]);
      const notes = await sql<{ day: string; text: string; coach_id: string }>`
        select to_char(day, 'YYYY-MM-DD') as day, text, coach_id from public.coach_notes where squad_id = ${squad}`.execute(
        trx,
      );
      expect(notes.rows).toStrictEqual([
        { day: '2026-11-01', text: '周日也跑了，米亚是认真的', coach_id: 'xiaohun' },
      ]);
      // The check-in's reply, its last line and emoji, never pushed.
      const replies = await sql<{
        check_in_id: string;
        text: string;
        emoji: string;
        coach_id: string;
      }>`
        select check_in_id, text, emoji, coach_id from public.coach_replies where squad_id = ${squad}`.execute(
        trx,
      );
      expect(replies.rows).toStrictEqual([
        {
          check_in_id: fixture.checkIn,
          text: '周日也跑，腿还在吗',
          emoji: '🔥',
          coach_id: 'xiaohun',
        },
      ]);
      // What members read: the newest line and the replies to the check-ins they ask about.
      const activity = createCoachActivity({ store: createPostgresCoachActivity(trx) });
      const xiaohun = { id: 'xiaohun', name: '小混', look: 'xiaohun' };
      const said = await activity.squad({
        squad,
        checkIns: [fixture.checkIn.toUpperCase(), randomUUID()],
      });
      expect(
        [said.note?.at, ...said.replies.map(({ at }) => at)].every((at) => at instanceof Date),
      ).toBe(true);
      expect({
        note: said.note === undefined ? undefined : { ...said.note, at: 'at' },
        replies: said.replies.map((reply) => ({ ...reply, at: 'at' })),
      }).toStrictEqual({
        note: {
          day: '2026-11-01',
          text: '周日也跑了，米亚是认真的',
          coach: xiaohun,
          at: 'at',
        },
        replies: [
          {
            checkIn: fixture.checkIn,
            coach: xiaohun,
            text: '周日也跑，腿还在吗',
            emoji: '🔥',
            mentions: [],
            at: 'at',
          },
        ],
      });
      expect(await activity.squad({ squad, checkIns: [] })).toMatchObject({ replies: [] });

      // One morning note a member, each only for them, waiting for their morning.
      const memberNotes = await sql<{ member_id: string; day: string; text: string }>`
        select member_id, to_char(day, 'YYYY-MM-DD') as day, text from public.coach_member_notes
        where squad_id = ${squad} order by member_id`.execute(trx);
      expect(memberNotes.rows).toStrictEqual(
        [
          { member_id: fixture.mia, day: '2026-11-01', text: '周日那趟跑得真稳' },
          { member_id: leo, day: '2026-11-01', text: '今天动一动？走走也算' },
        ].toSorted((a, b) => a.member_id.localeCompare(b.member_id)),
      );
      // Not on 今天 before it reached them; then only the reader's own.
      expect(
        (await activity.squad({ squad, checkIns: [], reader: fixture.mia })).memberNote,
      ).toBeUndefined();
      const delivery = createCoachNoteDelivery({ store: createPostgresCoachNoteDelivery(trx) });
      const waiting = await delivery.waiting(now);
      expect(
        waiting
          .map(({ member, text, coachName, day }) => ({ member, text, coachName, day }))
          .toSorted((a, b) => a.member.localeCompare(b.member)),
      ).toStrictEqual(
        [
          { member: fixture.mia, text: '周日那趟跑得真稳', coachName: '小混', day: '2026-11-01' },
          { member: leo, text: '今天动一动？走走也算', coachName: '小混', day: '2026-11-01' },
        ].toSorted((a, b) => a.member.localeCompare(b.member)),
      );
      const miaNote = waiting.find(({ member }) => member === fixture.mia);
      if (miaNote === undefined) throw new Error('no note for mia');
      expect(await delivery.delivered(miaNote.id)).toBe(true);
      expect(await delivery.delivered(miaNote.id)).toBe(false);
      expect((await delivery.waiting(now)).map(({ member }) => member)).toStrictEqual([leo]);
      const mine = await activity.squad({ squad, checkIns: [], reader: fixture.mia });
      expect({ ...mine.memberNote, at: 'at' }).toStrictEqual({
        id: miaNote.id,
        day: '2026-11-01',
        text: '周日那趟跑得真稳',
        coach: xiaohun,
        at: 'at',
      });
      expect(
        (await activity.squad({ squad, checkIns: [], reader: leo })).memberNote,
      ).toBeUndefined();
      // Seen on one phone (its card swiped away), it shows on none; another member's swipe
      // does nothing to it.
      const seen = { squad, kind: 'note', id: String(miaNote.id) } as const;
      await activity.markSeen({ ...seen, member: leo });
      expect(
        (await activity.squad({ squad, checkIns: [], reader: fixture.mia })).memberNote?.id,
      ).toBe(miaNote.id);
      await activity.markSeen({ ...seen, member: fixture.mia });
      await activity.markSeen({ ...seen, member: fixture.mia });
      expect(
        (await activity.squad({ squad, checkIns: [], reader: fixture.mia })).memberNote,
      ).toBeUndefined();
      // Never put away, it is gone from 今天 once its day is over (the bell keeps it).
      const leoNote = waiting.find(({ member }) => member === leo);
      if (leoNote === undefined) throw new Error('no note for leo');
      await delivery.delivered(leoNote.id);
      expect((await activity.squad({ squad, checkIns: [], reader: leo })).memberNote?.text).toBe(
        '今天动一动？走走也算',
      );
      expect(
        (
          await activity.squad({
            squad,
            checkIns: [],
            reader: leo,
            now: new Date(Date.now() + 19 * 60 * 60_000),
          })
        ).memberNote,
      ).toBeUndefined();
      // Each wake counted to the squad, the check-in's to its author.
      expect(
        fixture.counted.runs.map(({ squad: of, member, kind, model }) => ({
          of,
          member,
          kind,
          model,
        })),
      ).toStrictEqual([
        { of: squad, member: fixture.mia, kind: 'wake', model: 'openai/gpt-6-luna' },
        // The day's: its challenges set on the challenge model first, then the notes.
        { of: squad, member: undefined, kind: 'wake', model: 'openai/gpt-6-luna' },
        { of: squad, member: undefined, kind: 'wake', model: 'openai/gpt-6-luna' },
      ]);

      // Run again: nothing new to wake for, and nothing runs twice.
      expect(
        await wakes(fixture, { agent, at: new Date(now.getTime() + 10 * 60_000) }).run(),
      ).toStrictEqual({
        coaching: true,
        squads: 1,
        queued: 0,
        done: 0,
        failed: 0,
      });
      expect(runs).toHaveLength(2);
      // Once the coach is fired, its note leaves 今天 too (the bell keeps it).
      await createCoachHiring({
        hiring: createPostgresCoachHiring(trx),
        catalog: createPostgresCoachCatalog(trx),
      }).fire({ squad, by: MemberId.parse(fixture.mia) });
      expect(
        (await activity.squad({ squad, checkIns: [], reader: leo })).memberNote,
      ).toBeUndefined();
    });
  });

  it('wakes only squads that hired a coach, and keeps their memory for the next one', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      const by = MemberId.parse(mia);
      const hiring = createCoachHiring({
        hiring: createPostgresCoachHiring(trx),
        catalog: createPostgresCoachCatalog(trx),
      });
      const { agent, runs } = scriptedAgent(() => [
        { tool: 'edit_file', input: { path: 'memory.md', find: '', replace: '队名：squad' } },
      ]);
      await wakes(fixture, { agent }).run();
      expect(await hiring.fire({ squad, by })).toStrictEqual({ fired: 'xiaohun' });

      // Fired: the next day comes and no coach wakes.
      const tomorrow = new Date(now.getTime() + 86_400_000);
      expect(await wakes(fixture, { agent, at: tomorrow }).run()).toMatchObject({
        squads: 0,
        queued: 0,
      });
      expect(runs).toHaveLength(2);
      await expect(hiring.fire({ squad, by })).rejects.toBeInstanceOf(NoCoachHiredError);

      // A retired coach can't be hired; 小混 again can, and reads the squad's memory.
      await expect(
        hiring.hire({ squad, coach: CoachId.parse('nobody'), by }),
      ).rejects.toBeInstanceOf(CoachNotOfferedError);
      await hiring.hire({ squad, coach: CoachId.parse('xiaohun'), by });
      await expect(
        hiring.hire({ squad, coach: CoachId.parse('xiaohun'), by }),
      ).rejects.toBeInstanceOf(CoachAlreadyHiredError);
      await wakes(fixture, { agent, at: tomorrow }).run();
      // The day's wake added a line (a reply's wake edits no file); the new hire dreams over
      // yesterday with it, then wakes for the day.
      expect(runs[2]?.task).toContain('# 夜里\n今天是');
      expect(runs[2]?.task).toContain('### memory.md（你和大家之间的事）\n```\n队名：squad\n```');

      const report = await createCoachReport({
        store: createPostgresCoachReport(trx),
        usage: fixture.counted.usage,
      }).squad(squad, tomorrow);
      expect(report).toMatchObject({
        coach: 'xiaohun',
        files: [
          { path: 'memory.md', body: '队名：squad\n队名：squad\n队名：squad' },
          // Started once, on the first wake.
          { path: 'squad.md' },
        ],
        usage: {
          // Each day's wake counts twice: its challenges set, then its notes.
          total: {
            wakes: 6,
            requests: 12,
            inputTokens: 72_000,
            cachedInputTokens: 0,
            outputTokens: 4_800,
            costMicros: 27_600,
          },
        },
      });
      const hires = await sql<{ kind: string }>`
        select kind from public.squad_coach_events where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(hires.rows.map(({ kind }) => kind)).toStrictEqual(['hired', 'fired', 'hired']);
    });
  });

  it('keeps each coach’s own page for that coach alone, and gives it back when it returns', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      const by = MemberId.parse(mia);
      const catalog = createPostgresCoachCatalog(trx);
      const hiring = createCoachHiring({ hiring: createPostgresCoachHiring(trx), catalog });
      const [first] = await catalog.list();
      if (first === undefined) throw new Error('No coach.');
      const nuannuan = CoachId.parse('nuannuan');
      await catalog.save({ ...first, id: nuannuan, name: '暖暖' }, by);
      let says = '我最会偷懒';
      const { agent, runs } = scriptedAgent(() => [
        { tool: 'remember', input: { path: 'me.md', fact: says } },
      ]);
      await wakes(fixture, { agent }).run();
      expect(runs[0]?.answers).toStrictEqual(['记下了，在 me.md。']);

      // 小混's 战术板 lines, which 暖暖 must not take for its own voice.
      await sql`insert into public.coach_notes (squad_id, coach_id, day, text)
        values (${squad}, 'xiaohun', '2026-10-30', '我先把沙发热好')`.execute(trx);

      // 暖暖 takes over: it never reads 小混's page or lines, and starts its own.
      await hiring.change({ squad, coach: nuannuan, by });
      says = '我说话慢';
      const seen = runs.length;
      await wakes(fixture, { agent, at: new Date(now.getTime() + 86_400_000) }).run();
      const hers = runs.slice(seen);
      // Its daily wake, which is told the lines it wrote lately, is among them.
      expect(hers.some(({ task }) => task.includes('新的一天'))).toBe(true);
      for (const run of hers) {
        expect(run.task).not.toContain('我最会偷懒');
        expect(run.task).not.toContain('我先把沙发热好');
      }

      // 小混 comes back to his own page, never hers.
      await hiring.change({ squad, coach: CoachId.parse('xiaohun'), by });
      const back = runs.length;
      await wakes(fixture, { agent, at: new Date(now.getTime() + 2 * 86_400_000) }).run();
      const his = runs[back];
      expect(his?.task).toContain(
        '### me.md（你自己：大家喜欢怎么跟你打交道、怎么看你这个教练，只有你读得到）\n```\n- 我最会偷懒',
      );
      expect(his?.task).not.toContain('我说话慢');

      const pages = await sql<{ path: string; member_id: string | null }>`
        select distinct path, member_id from public.coach_files
        where squad_id = ${squad} and path like 'coaches/%' order by path`.execute(trx);
      expect(pages.rows).toStrictEqual([
        { path: 'coaches/nuannuan.md', member_id: null },
        { path: 'coaches/xiaohun.md', member_id: null },
      ]);
    });
  });

  it('knows when a coach was hired back, and is greeted as one until it first runs', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      const by = MemberId.parse(mia);
      const catalog = createPostgresCoachCatalog(trx);
      const store = createPostgresCoachHiring(trx);
      const hiring = createCoachHiring({ hiring: store, catalog });
      const xiaohun = CoachId.parse('xiaohun');
      const nuannuan = CoachId.parse('nuannuan');
      const [first] = await catalog.list();
      if (first === undefined) throw new Error('No coach.');
      await catalog.save({ ...first, id: nuannuan, name: '暖暖' }, by);

      // Its first coach is new to the squad, and so is the next.
      expect(await store.hiredBackAt(squad)).toBeUndefined();
      await hiring.change({ squad, coach: nuannuan, by });
      expect(await store.hiredBackAt(squad)).toBeUndefined();
      // The first one hired again is back.
      await hiring.change({ squad, coach: xiaohun, by });
      const { rows } = await sql<{ now: Date }>`select now() as now`.execute(trx);
      expect(await store.hiredBackAt(squad)).toStrictEqual(rows[0]?.now);

      // Its first wake tells it it is back; once it has run for the squad, it is just its coach.
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, { agent }).run();
      expect(runs[0]?.task).toContain(BACK_AGAIN);
      expect(runs.slice(1).some(({ task }) => task.includes(BACK_AGAIN))).toBe(false);

      // No coach, nothing to be back.
      await hiring.fire({ squad, by });
      expect(await store.hiredBackAt(squad)).toBeUndefined();
    });
  });

  it('tells a coach whom it took over from and the letter it was left', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      const by = MemberId.parse(mia);
      const catalog = createPostgresCoachCatalog(trx);
      const hiring = createCoachHiring({ hiring: createPostgresCoachHiring(trx), catalog });
      const letters = createPostgresCoachLetters(trx);
      const nuannuan = CoachId.parse('nuannuan');
      const [first] = await catalog.list();
      if (first === undefined) throw new Error('No coach.');
      await catalog.save({ ...first, id: nuannuan, name: '暖暖' }, by);

      // The fixture's first coach came with none before it: nothing to tell.
      const quiet = scriptedAgent(() => []);
      await wakes(fixture, { agent: quiet.agent }).run();
      expect(quiet.runs.length).toBeGreaterThan(0);
      expect(quiet.runs.some(({ task }) => task.includes('你接手这个小队'))).toBe(false);

      // 换教练 to 暖暖, then back to 小混: 小混 took over from 暖暖, whose letter isn't in yet,
      // so nothing is said of one.
      await hiring.change({ squad, coach: nuannuan, by });
      await hiring.change({ squad, coach: CoachId.parse('xiaohun'), by });
      const { rows } = await sql<{ day: string }>`
        select to_char(now() at time zone 'America/New_York', 'YYYY-MM-DD') as day`.execute(trx);
      const day = rows[0]?.day;
      if (day === undefined) throw new Error('No day.');
      await sql`delete from public.coach_wakes where squad_id = ${squad}`.execute(trx);
      const before = scriptedAgent(() => []);
      await wakes(fixture, { agent: before.agent }).run();
      // A reply's wake (the first here) tells it among what is special about today.
      expect(before.runs[0]?.task).toContain(`## 今天\n- ${day} 小队换教练，你接替了暖暖。`);
      expect(before.runs[0]?.task).not.toContain('暖暖走时');

      // Once 暖暖's letter is in, the next wake reads it as the squad did.
      const handover = await letters.handover(squad);
      if (handover === undefined) throw new Error('No handover.');
      await letters.claim(handover);
      await letters.save({ handover, day, text: '小混，这队交给你了，大家都爱练腿。' });
      await sql`delete from public.coach_wakes where squad_id = ${squad}`.execute(trx);
      const after = scriptedAgent(() => []);
      await wakes(fixture, { agent: after.agent }).run();
      expect(after.runs[0]?.task).toContain(
        '暖暖走时给全队留了一封信，大家都看过：\n「小混，这队交给你了，大家都爱练腿。」',
      );
    });
  });

  it('changes the coach in one step for 换教练, and says when it already had it', async () => {
    await rolledBack(async ({ trx, squad, mia }) => {
      const by = MemberId.parse(mia);
      const catalog = createPostgresCoachCatalog(trx);
      const hiring = createCoachHiring({ hiring: createPostgresCoachHiring(trx), catalog });
      const xiaohun = CoachId.parse('xiaohun');
      const nuannuan = CoachId.parse('nuannuan');
      const [first] = await catalog.list();
      if (first === undefined) throw new Error('No coach.');
      await catalog.save({ ...first, id: nuannuan, name: '暖暖' }, by);

      expect((await hiring.offered()).map(({ id }) => id)).toStrictEqual([nuannuan, xiaohun]);
      expect(await hiring.current(squad)).toMatchObject({ coach: { id: xiaohun } });
      expect(await hiring.change({ squad, coach: xiaohun, by })).toMatchObject({
        coach: { id: xiaohun },
        changed: false,
      });
      expect(await hiring.change({ squad, coach: nuannuan, by })).toMatchObject({
        coach: { id: nuannuan, name: '暖暖' },
        changed: true,
      });
      expect(await hiring.current(squad)).toMatchObject({ coach: { id: nuannuan } });

      // A retired coach can't be hired; the squad keeps the one it has.
      await catalog.save({ ...first, offered: false }, by);
      await expect(hiring.change({ squad, coach: xiaohun, by })).rejects.toBeInstanceOf(
        CoachNotOfferedError,
      );
      expect((await hiring.offered()).map(({ id }) => id)).toStrictEqual([nuannuan]);
      // Retired since it was hired, the squad's own coach is still a retry, never a refusal.
      const hiredNow = (await catalog.list()).find(({ id }) => id === nuannuan);
      if (hiredNow === undefined) throw new Error('No 暖暖.');
      await catalog.save({ ...hiredNow, offered: false }, by);
      expect(await hiring.change({ squad, coach: nuannuan, by })).toMatchObject({
        coach: { id: nuannuan },
        changed: false,
      });

      // A squad that isn't there is refused before anything is written, so the transaction
      // it ran in goes on.
      await catalog.save(hiredNow, by);
      await expect(
        hiring.change({ squad: SquadId.parse(randomUUID()), coach: nuannuan, by }),
      ).rejects.toBeInstanceOf(CoachSquadNotFoundError);
      expect(await hiring.current(squad)).toMatchObject({ coach: { id: nuannuan } });

      // The fixture's hire, then the change: fired and hired in order, each by the member.
      const events = await sql<{ kind: string; coach_id: string; changed_by: string }>`
        select kind, coach_id, changed_by from public.squad_coach_events
        where squad_id = ${squad} order by id`.execute(trx);
      expect(events.rows).toStrictEqual([
        { kind: 'hired', coach_id: 'xiaohun', changed_by: mia },
        { kind: 'fired', coach_id: 'xiaohun', changed_by: mia },
        { kind: 'hired', coach_id: 'nuannuan', changed_by: mia },
      ]);

      await hiring.fire({ squad, by });
      expect(await hiring.current(squad)).toBeUndefined();
    });
  });

  it('welcomes a member who joins at once, introducing itself in a note only they read', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, leo } = fixture;
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('刚加入小队')
          ? [{ tool: 'note_to', input: { member: '队员2', text: '我是小混，欢迎你来' } }]
          : [],
      );
      const told: Parameters<CoachWelcomed>[0][] = [];
      const welcomed: CoachWelcomed = (welcome) => {
        told.push(welcome);
        return Promise.resolve();
      };
      // What they did before joining, since the coach knows nothing of them yet.
      const memberFacts: CoachMemberFacts = ({ members }) =>
        Promise.resolve(
          members.map((member) => ({
            member,
            trainedDays: 46,
            topSport: { name: '游泳', checkIns: 30 },
            healthyMeals: 0,
            cheatMeals: 0,
            disclaimers: 0,
            titles: 0,
            plan: [],
            fuelGoals: [],
          })),
        );
      const coach = wakes(fixture, { agent, welcomed, memberFacts, at: now });
      await coach.welcome({ squad, member: leo });
      expect(runs).toHaveLength(1);
      expect(runs[0]?.task).toContain('# 队员2刚加入小队\n今天是 2026-11-01，周日。');
      expect(runs[0]?.task).toContain(
        '## 新人\n\n### 队员2\n- 以前一共练了：46 天，练得最多的是游泳（30 次）\n',
      );
      expect(runs[0]?.task).toContain('给他写一张便条（note_to）：先介绍你自己，再欢迎他。');
      // Only the note: no 战术板, no gift, no reply.
      expect(runs[0]?.tools).toContain('note_to');
      expect(runs[0]?.tools).not.toContain('post_note');
      expect(runs[0]?.tools).not.toContain('reply');
      expect(runs[0]?.answers).toStrictEqual(['便条写好了，给 队员2。']);
      const notes = await sql<{ id: string; challenge_title: string | null; delivered: boolean }>`
        select n.id, n.challenge_title, d.note_id is not null as delivered
        from public.coach_member_notes n
        left join public.coach_member_note_deliveries d on d.note_id = n.id
        where n.member_id = ${leo}`.execute(trx);
      expect(
        notes.rows.map(({ challenge_title, delivered }) => ({ challenge_title, delivered })),
      ).toStrictEqual([{ challenge_title: null, delivered: true }]);
      expect(told).toStrictEqual([
        {
          squad,
          member: leo,
          coach: 'xiaohun',
          note: Number(notes.rows[0]?.id),
          day: '2026-11-01',
          text: '我是小混，欢迎你来',
        },
      ]);
      // Delivered already, so the morning delivery never pushes it.
      const delivery = createCoachNoteDelivery({ store: createPostgresCoachNoteDelivery(trx) });
      expect((await delivery.waiting(now)).filter(({ member }) => member === leo)).toStrictEqual(
        [],
      );
      // Joining again the same day isn't welcomed twice.
      await coach.welcome({ squad, member: leo });
      expect(runs).toHaveLength(1);
      // A member whose account went before the welcome was queued gets none, and nothing throws.
      await coach.welcome({ squad, member: randomUUID() });
      expect(runs).toHaveLength(1);
    });
  });

  it('welcomes no one who hasn’t agreed to AI use, nor while coaching is off', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, leo } = fixture;
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, { agent, consented: [mia] }).welcome({ squad, member: leo });
      expect(runs).toHaveLength(0);
      await createCoachSettings({ store: createPostgresCoachSettings(trx) }).change(
        { coaching: false },
        MemberId.parse(mia),
      );
      await wakes(fixture, { agent, at: new Date(now.getTime() + 86_400_000) }).welcome({
        squad,
        member: leo,
      });
      expect(runs).toHaveLength(0);
      const queued = await sql<{ n: number }>`
        select count(*)::int as n from public.coach_wakes where squad_id = ${squad} and reason = 'joined'`.execute(
        trx,
      );
      // The first was queued and let go; none while coaching is off.
      expect(queued.rows[0]?.n).toBe(1);
    });
  });

  it('answers an @ of it at once, even where it said nothing yet, and the job catches a missed one', async () => {
    await rolledBack(async (fixture) => {
      const { squad, leo, checkIn } = fixture;
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('要回的这句')
          ? [{ tool: 'reply', input: { point: '接住', text: '下雨就练核心' } }]
          : [],
      );
      const told: Parameters<CoachAnswered>[0][] = [];
      const answered: CoachAnswered = (answer) => {
        told.push(answer);
        return Promise.resolve();
      };
      const asked = await commentOn(fixture, {
        member: leo,
        text: '@小混 下雨还练吗',
        at: new Date(now.getTime() + 60_000),
        mentionsCoach: 'xiaohun',
      });
      const withAsk: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, comments: [asked] })),
      };
      const coach = wakes(
        { ...fixture, week: withAsk },
        { agent, answered, at: new Date(now.getTime() + 2 * 60_000) },
      );
      // Not in a squad that isn't the post's, nor for another coach.
      await coach.answer({ checkIn, comment: asked.id, coach: 'xiaohun', squads: [] });
      await coach.answer({ checkIn, comment: asked.id, coach: 'maotou', squads: [squad] });
      expect(runs).toHaveLength(0);
      await coach.answer({ checkIn, comment: asked.id, coach: 'xiaohun', squads: [squad] });
      const answering = runs.find(({ task }) => task.includes('要回的这句'));
      expect(answering?.task).toContain('# 队员2在动态1下面 @ 你');
      expect(answering?.task).toContain(
        '## 评论区（先后顺序）\n- 11-01 周日 10:01 队员2（@你）：「@小混 下雨还练吗」（要回的这句）',
      );
      expect(told).toStrictEqual([
        {
          squad,
          checkIn,
          comment: asked.id,
          commenter: leo,
          coach: 'xiaohun',
          text: '下雨就练核心',
          mentions: [],
        },
      ]);

      // Its answer is something it said here, so a reply to that is answered too, though it
      // never replied to the check-in itself.
      const { mia } = fixture;
      const back = await commentOn(fixture, {
        member: mia,
        text: '那她呢',
        at: new Date(now.getTime() + 3 * 60_000),
        toCoach: 'xiaohun',
      });
      const withBack: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, comments: [asked, back] })),
      };
      await wakes(
        { ...fixture, week: withBack },
        { agent, answered, at: new Date(now.getTime() + 4 * 60_000) },
      ).answer({ checkIn, comment: back.id, coach: 'xiaohun', squads: [squad] });
      expect(told.map(({ comment }) => comment)).toStrictEqual([asked.id, back.id]);
    });
  });

  it('answers each reply to it at once, with the talk so far, and tells who wrote it', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, leo, checkIn } = fixture;
      const { agent, runs } = scriptedAgent((task) => {
        if (task.includes('发了动态'))
          return [{ tool: 'reply', input: { point: '接住', text: '周日也跑？' } }];
        if (task.includes('要回的这句')) {
          return [
            { tool: 'react', input: { emoji: '🔥' } },
            { tool: 'reply', input: { point: '接住', text: '队员2 你也来' } },
            {
              tool: 'reply',
              input: { point: '接住', text: task.includes('你喊') ? '喊破嗓子' : '你也来跑' },
            },
          ];
        }
        return [];
      });
      const told: Parameters<CoachAnswered>[0][] = [];
      const answered: CoachAnswered = (answer) => {
        told.push(answer);
        return Promise.resolve();
      };
      // Nothing to reply to before the coach says anything.
      const early = await commentOn(fixture, {
        member: leo,
        text: '教练在吗',
        at: new Date(now.getTime() - 5 * 60_000),
        toCoach: 'xiaohun',
      });
      const before: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, comments: [early] })),
      };
      await wakes({ ...fixture, week: before }, { agent, answered }).answer({
        checkIn,
        comment: early.id,
        coach: 'xiaohun',
        squads: [fixture.squad],
      });
      expect(runs).toHaveLength(0);
      await sql`delete from public.check_in_comments where id = ${early.id}`.execute(trx);

      await wakes(fixture, { agent }).run();
      const first = await commentOn(fixture, {
        member: leo,
        text: '你也跑吗',
        at: new Date(now.getTime() + 60_000),
        toCoach: 'xiaohun',
      });
      const later = new Date(now.getTime() + 2 * 60_000);
      const withFirst: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, comments: [first] })),
      };
      await wakes({ ...fixture, week: withFirst }, { agent, answered, at: later }).answer({
        checkIn,
        comment: first.id,
        coach: 'xiaohun',
        squads: [fixture.squad],
      });
      // Another coach, or one the squad didn't hire, has nothing to answer.
      await wakes({ ...fixture, week: withFirst }, { agent, answered, at: later }).answer({
        checkIn,
        comment: first.id,
        coach: 'maotou',
        squads: [fixture.squad],
      });
      // Nor one in a squad the writer isn't in, which shares the check-in with theirs.
      const ran = runs.length;
      const outside = await commentOn(fixture, {
        member: leo,
        text: '我在别的队',
        at: new Date(now.getTime() + 150_000),
        toCoach: 'xiaohun',
      });
      const withoutLeo: SquadWeek = {
        ...withFirst,
        members: withFirst.members.filter(({ member }) => member !== leo),
        checkIns: withFirst.checkIns.map((each) => ({ ...each, comments: [first, outside] })),
      };
      await wakes({ ...fixture, week: withoutLeo }, { agent, answered, at: later }).answer({
        checkIn,
        comment: outside.id,
        coach: 'xiaohun',
        squads: [fixture.squad],
      });
      expect(runs).toHaveLength(ran);
      await sql`delete from public.check_in_comments where id = ${outside.id}`.execute(trx);
      const second = await commentOn(fixture, {
        member: mia,
        text: '那你喊大声点',
        at: new Date(now.getTime() + 3 * 60_000),
        toCoach: 'xiaohun',
      });
      const withBoth: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, comments: [first, second] })),
      };
      const coach = wakes(
        { ...fixture, week: withBoth },
        { agent, answered, at: new Date(now.getTime() + 4 * 60_000) },
      );
      await coach.answer({ checkIn, comment: second.id, coach: 'xiaohun', squads: [squad] });
      // Answered once: the next run, or the same reply again, finds it answered.
      await coach.answer({ checkIn, comment: second.id, coach: 'xiaohun', squads: [squad] });
      await coach.run();

      // The check-in's wake, the day's, then one for each reply.
      expect(runs.map(({ tools }) => tools.at(-1))).toStrictEqual([
        'react',
        'note_to',
        'reply',
        'reply',
      ]);
      expect(runs[2]?.task).toContain(
        '- 你：「周日也跑？」\n- 11-01 周日 10:01 队员2（回复你）：「你也跑吗」（要回的这句）',
      );
      expect(runs[3]?.task).toContain(
        '- 你：「周日也跑？」\n- 11-01 周日 10:01 队员2（回复你）：「你也跑吗」\n- 你：「你也来跑」\n- 11-01 周日 10:03 米亚（回复你）：「那你喊大声点」（要回的这句）',
      );
      // No react on a reply's wake; a line may not name 队员N, as any line members read.
      expect(runs[2]?.answers).toStrictEqual([
        'no tool react',
        '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。',
        '已回复。',
      ]);
      expect(told).toStrictEqual([
        {
          squad,
          checkIn,
          comment: first.id,
          commenter: leo,
          coach: 'xiaohun',
          text: '你也来跑',
          mentions: [],
        },
        {
          squad,
          checkIn,
          comment: second.id,
          commenter: mia,
          coach: 'xiaohun',
          text: '喊破嗓子',
          mentions: [],
        },
      ]);
      // The next day's wake goes over the last day's talk, to remember what it missed.
      await wakes(
        { ...fixture, week: withBoth },
        { agent, at: new Date(now.getTime() + 20 * 3_600_000) },
      ).run();
      expect(runs.at(-1)?.task).toContain(
        '## 和你的对话（过去一天，打卡下面，先后顺序）\n\n### 11-01 周日 · 米亚 · 训练：跑步',
      );
      expect(runs.at(-1)?.task).toContain(
        '- 你：「周日也跑？」\n- 队员2（回复你）：「你也跑吗」\n- 你：「你也来跑」\n- 米亚（回复你）：「那你喊大声点」\n- 你：「喊破嗓子」',
      );
      // A post's wake reads what its author and the coach said to each other under other posts
      // that day, theirs only: so it follows on from there (2026-11-14: it marked a challenge
      // done that she had said she'd skip under another post).
      const postBy = async (member: string, minutes: number) => {
        const id = randomUUID();
        const createdAt = new Date(now.getTime() + minutes * 60_000);
        await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
          values (${id}, ${member}, '2026-11-01', ${createdAt}, 'healthyMeal', '{"version": 1}')`.execute(
          trx,
        );
        const week: SquadWeek = {
          ...withBoth,
          checkIns: [
            ...withBoth.checkIns,
            {
              id,
              member,
              day: '2026-11-01',
              createdAt,
              kind: 'healthyMeal',
              reactedBy: [],
              comments: [],
            },
          ],
        };
        await wakes(
          { ...fixture, week },
          { agent, at: new Date(createdAt.getTime() + 60_000) },
        ).checkedIn({ checkIn: id, squads: [squad] });
        return runs.at(-1)?.task;
      };
      // Pointed to by number, looked up with post_comments, never pasted in.
      expect(await postBy(mia, 5)).toContain(
        '\n- 过去一天你们还在 动态1 下面聊过（post_comments 可看）\n',
      );
      const leos = await postBy(leo, 6);
      expect(leos).toContain('\n- 过去一天你们还在 动态1 下面聊过（post_comments 可看）\n');
      expect(leos).not.toContain('你也来跑');
      const activity = await createCoachActivity({
        store: createPostgresCoachActivity(trx),
      }).squad({ squad, checkIns: [checkIn] });
      expect(
        activity.answers.map(({ comment, text, coach: { id } }) => ({ comment, text, id })),
      ).toStrictEqual([
        { comment: first.id, text: '你也来跑', id: 'xiaohun' },
        { comment: second.id, text: '喊破嗓子', id: 'xiaohun' },
      ]);
      // Members may reply only to a coach that wrote a line here.
      const spoke = createCoachActivity({ store: createPostgresCoachActivity(trx) });
      expect(await spoke.spoke({ squads: [squad], checkIn, coach: 'xiaohun' })).toBe(true);
      expect(await spoke.spoke({ squads: [squad], checkIn, coach: 'maotou' })).toBe(false);
      expect(await spoke.spoke({ squads: [], checkIn, coach: 'xiaohun' })).toBe(false);

      // An answer goes with the reply it answers, and is never changed.
      await sql`savepoint attempt`.execute(trx);
      await expect(
        sql`update public.coach_answers set text = '改了' where comment_id = ${first.id}`.execute(
          trx,
        ),
      ).rejects.toThrow('coach_answers is append-only');
      await sql`rollback to savepoint attempt`.execute(trx);
      await sql`delete from public.check_in_comments where id = ${first.id}`.execute(trx);
      const left = await sql<{ comment_id: string }>`
        select comment_id from public.coach_answers where squad_id = ${squad}`.execute(trx);
      expect(left.rows).toStrictEqual([{ comment_id: second.id }]);
    });
  });

  it('saves nothing but the tokens of a failed run, and tries a wake three times', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad } = fixture;
      const { agent, runs } = scriptedAgent(() => 'fail');
      for (const minutes of [0, 10, 20, 30]) {
        await wakes(fixture, { agent, at: new Date(now.getTime() + minutes * 60_000) }).run();
      }
      // Two wakes, three tries each; the fourth run has nothing left to try.
      expect(runs).toHaveLength(6);
      const states = await sql<{
        reason: string;
        state: string;
        tries: number;
        last_error: string;
      }>`
        select reason, state, tries, last_error from public.coach_wakes where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(states.rows).toStrictEqual([
        { reason: 'checkIn', state: 'failed', tries: 3, last_error: 'ModelBehaviorError: no' },
        // Nothing from yesterday to dream over: done without a run.
        { reason: 'dream', state: 'done', tries: 1, last_error: null },
        { reason: 'daily', state: 'failed', tries: 3, last_error: 'ModelBehaviorError: no' },
      ]);
      const counts = await sql<{ files: string; notes: string }>`
        select (select count(*) from public.coach_files where squad_id = ${squad}) as files,
          (select count(*) from public.coach_notes where squad_id = ${squad}) as notes`.execute(
        trx,
      );
      expect(counts.rows).toStrictEqual([{ files: '0', notes: '0' }]);
      // A failed run's tokens were spent all the same: every try counted, with each daily try's
      // challenges set before it.
      expect(fixture.counted.runs).toHaveLength(9);
    });
  });

  it('skips its wakes while the squad’s AI budget is spent, saying why, and runs once it isn’t', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad } = fixture;
      let spent = true;
      const { usage } = countedUsage(() =>
        spent ? 'the squad spent 4600 of its 4600 micros today' : undefined,
      );
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, { agent, usage }).run();
      expect(runs).toHaveLength(0);
      spent = false;
      await wakes(fixture, { agent, usage, at: new Date(now.getTime() + 86_400_000) }).run();
      // The next day: the night's dream over the check-in, then the daily wake.
      expect(runs).toHaveLength(2);
      const states = await sql<{ reason: string; state: string; last_error: string | null }>`
        select reason, state, last_error from public.coach_wakes where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(states.rows).toStrictEqual([
        {
          reason: 'checkIn',
          state: 'skipped',
          last_error: 'off duty: the squad spent 4600 of its 4600 micros today',
        },
        {
          reason: 'dream',
          state: 'skipped',
          last_error: 'off duty: the squad spent 4600 of its 4600 micros today',
        },
        {
          reason: 'daily',
          state: 'skipped',
          last_error: 'off duty: the squad spent 4600 of its 4600 micros today',
        },
        { reason: 'dream', state: 'done', last_error: null },
        { reason: 'daily', state: 'done', last_error: null },
      ]);
    });
  });

  it('never wakes for a squad that ended, though its coach is still on record', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => []);
      const run = await wakes(fixture, { agent, ended: true }).run();
      expect(run).toMatchObject({ coaching: true, squads: 0, queued: 0 });
      expect(runs).toHaveLength(0);
      await wakes(fixture, { agent, ended: true, at: new Date(now.getTime() + 86_400_000) }).run();
      expect(runs).toHaveLength(0);
      // Nor for a check-in whose event comes in after everyone left.
      await wakes(fixture, { agent, ended: true }).checkedIn({
        checkIn: fixture.checkIn,
        squads: [fixture.squad],
      });
      expect(runs).toHaveLength(0);
    });
  });

  it('looks at a check-in at once, shows its recent emoji, and keeps every tool call', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, checkIn } = fixture;
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('发了动态')
          ? [
              { tool: 'member_posts', input: { member: '米亚' } },
              { tool: 'react', input: { emoji: '🔥' } },
              { tool: 'reply', input: { point: '接住', text: '队员1 好' } },
              { tool: 'remember', input: { path: 'memory.md', fact: '米亚怕下雨' } },
            ]
          : [],
      );
      const other = SquadId.parse(randomUUID());
      await sql`insert into public.squads (id, name, invite_code) values (${other}, 'other', ${other})`.execute(
        trx,
      );
      // Only the check-in's wake runs, in the squad that hired a coach; the day's waits for the job.
      await wakes(fixture, { agent }).checkedIn({ checkIn, squads: [other, squad] });
      expect(runs).toHaveLength(1);
      expect(runs[0]?.task).toContain('## 你最近点过的表情\n还没点过。');

      // A second check-in sees the emoji the coach used, newest first.
      const second = randomUUID();
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${second}, ${mia}, '2026-11-01', ${now}, 'healthyMeal', '{"version": 1}')`.execute(
        trx,
      );
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: [
          ...fixture.week.checkIns,
          {
            id: second,
            member: mia,
            day: '2026-11-01',
            createdAt: now,
            kind: 'healthyMeal',
            reactedBy: [],
            comments: [],
          },
        ],
      };
      await wakes({ ...fixture, week }, { agent }).checkedIn({ checkIn: second, squads: [squad] });
      expect(runs).toHaveLength(2);
      expect(runs[1]?.task).toContain('## 你最近点过的表情\n🔥');

      // Each call, with what the tool answered: a read by its length only.
      const report = await createPostgresCoachReport(trx).squad(squad);
      expect(report.wakes[1]?.steps).toStrictEqual([
        { tool: 'member_posts', input: { member: '米亚' }, output: '（78 字）' },
        { tool: 'react', input: { emoji: '🔥' }, output: '已点 🔥。' },
        {
          tool: 'reply',
          input: { point: '接住', text: '队员1 好' },
          output: '队员看不到「队员N」这种叫法：直接说「你」，或者叫昵称。',
        },
        // A fact by its length: it may be a member's words.
        {
          tool: 'remember',
          input: { path: 'memory.md', fact: '（5 字）' },
          output: '记下了，在 memory.md。',
        },
      ]);
      expect(JSON.stringify(report.wakes)).not.toContain('跑步');
      expect(JSON.stringify(report.wakes)).not.toContain('怕下雨');
    });
  });

  it('looks at a check-in’s photos only when it asks, once, and keeps only how many', async () => {
    await rolledBack(async (fixture) => {
      const { squad, checkIn } = fixture;
      const asked: (readonly string[])[] = [];
      const photoUrls: CoachPhotoUrls = (paths) => {
        asked.push(paths);
        return Promise.resolve(paths.map((path) => `https://photos.test/${path}`));
      };
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('发了动态')
          ? [
              { tool: 'look_at_photos', input: {} },
              { tool: 'look_at_photos', input: {} },
              { tool: 'reply', input: { point: '接住', text: '这碗面看着不错' } },
            ]
          : [],
      );
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) =>
          each.id === checkIn ? { ...each, photos: ['m/a.jpg', 'm/b.jpg'] } : each,
        ),
      };
      await wakes({ ...fixture, week }, { agent, photoUrls }).checkedIn({
        checkIn,
        squads: [squad],
      });
      expect(runs[0]?.task).toContain('- 照片 2 张，你还没看过（look_at_photos）');
      expect(runs[0]?.task).not.toContain('m/a.jpg');
      expect(runs[0]?.tools).toContain('look_at_photos');
      expect(runs[0]?.answers).toStrictEqual([
        '这条打卡的 2 张照片，第一张是封面： https://photos.test/m/a.jpg https://photos.test/m/b.jpg',
        '照片你已经看过了，不用再看。',
        '已回复。',
      ]);
      expect(asked).toStrictEqual([['m/a.jpg', 'm/b.jpg']]);
      const report = await createPostgresCoachReport(fixture.trx).squad(squad);
      expect(report.wakes[0]?.steps.slice(0, 2)).toStrictEqual([
        { tool: 'look_at_photos', input: {}, output: '（2 张照片）' },
        { tool: 'look_at_photos', input: {}, output: '已经看过了。' },
      ]);
    });
  });

  it('looks up members’ stats and an earlier week only when it asks', async () => {
    await rolledBack(async (fixture) => {
      const { squad, mia } = fixture;
      const asked: unknown[] = [];
      const memberFacts: CoachMemberFacts = (input) => {
        asked.push(input);
        return Promise.resolve(
          input.members.map((member) => ({
            member,
            trainedDays: 50,
            healthyMeals: 0,
            cheatMeals: 0,
            disclaimers: 0,
            titles: 0,
            plan: Array.from({ length: 7 }, () => ({ kind: 'rest' as const })),
            fuelGoals: [],
          })),
        );
      };
      // The day's wake has them; a reply's wake reads what it needs from the task.
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('新的一天')
          ? [
              { tool: 'member_stats', input: {} },
              { tool: 'squad_week', input: { weeks_ago: 1 } },
            ]
          : [],
      );
      const earlier = '2026-10-19';
      await wakes(fixture, {
        agent,
        memberFacts,
        consented: [mia],
        weeks: {
          [fixture.week.weekStart]: fixture.week,
          [earlier]: { weekStart: earlier, members: fixture.week.members, checkIns: [] },
        },
      }).run();
      const daily = runs.find(({ task }) => task.includes('新的一天'));
      expect(asked).toContainEqual({ squad, members: [mia], weekStart: fixture.week.weekStart });
      expect(daily?.answers[0]).toContain('一共练了 50 天');
      expect(daily?.answers[1]).toContain(`- 从 ${earlier}（周一）开始`);
    });
  });

  it('looks up a member’s posts, and the comments under one, only when it asks', async () => {
    await rolledBack(async (fixture) => {
      const { squad, checkIn, mia, leo } = fixture;
      const comment = await commentOn(fixture, {
        member: mia,
        text: '跟队员2比谁更健康',
        at: new Date(now.getTime() - 5 * 60_000),
      });
      // A commenter without an AI consent, under a post whose author has one.
      const unconsented = await commentOn(fixture, {
        member: leo,
        text: '没同意的人的评论',
        at: new Date(now.getTime() - 4 * 60_000),
      });
      const earlier = '2026-10-19';
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: [
          ...fixture.week.checkIns.map((each) => ({ ...each, comments: [comment, unconsented] })),
          {
            id: randomUUID(),
            member: leo,
            day: '2026-10-31',
            createdAt: new Date('2026-10-31T15:00:00Z'),
            kind: 'healthyMeal',
            text: '没同意的人的饭',
            reactedBy: [],
            comments: [],
          },
        ],
      };
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('发了动态')
          ? [
              { tool: 'member_posts', input: { member: '米亚' } },
              { tool: 'post_comments', input: { post: '动态1' } },
              { tool: 'post_comments', input: { post: '动态2' } },
              { tool: 'post_comments', input: { post: '动态9' } },
              { tool: 'member_posts', input: { member: '队员2', weeks: 0 } },
              { tool: 'member_posts', input: { member: '队员7' } },
            ]
          : [],
      );
      await wakes(fixture, {
        agent,
        consented: [mia],
        weeks: {
          [week.weekStart]: week,
          [earlier]: {
            weekStart: earlier,
            members: week.members,
            checkIns: [
              {
                id: randomUUID(),
                member: mia,
                day: '2026-10-20',
                createdAt: new Date('2026-10-20T15:00:00Z'),
                kind: 'trained',
                sport: '游泳',
                minutes: 30,
                unposted: true,
                reactedBy: [],
                comments: [],
              },
            ],
          },
        },
      }).checkedIn({ checkIn, squads: [squad] });
      expect(runs[0]?.answers).toStrictEqual([
        [
          '# 米亚 的动态（新的在前）',
          '## 动态1 · 11-01 周日 · 米亚 · 训练：跑步\n- 评论：1 条（用 post_comments 看）',
          '## 动态2 · 10-20 周二 · 米亚 · 训练：游泳 30 分钟\n- 只记录，没发动态',
        ].join('\n\n'),
        '动态1 的评论区：\n- 11-01 周日 09:55 米亚：「跟队员2比谁更健康」',
        '动态2 只记录，没发动态，没有评论。',
        '没有 动态9；能看的是：动态1、动态2。',
        // Without an AI consent, nothing they posted is read.
        '队员2 这段时间没有能看的动态。',
        '没有 队员7；队员是：米亚、队员2。',
      ]);
      expect(JSON.stringify(runs)).not.toContain('没同意的人');
      const report = await createPostgresCoachReport(fixture.trx).squad(squad);
      expect(report.wakes[0]?.steps[1]).toStrictEqual({
        tool: 'post_comments',
        input: { post: '动态1' },
        output: '（41 字）',
      });
    });
  });

  it('reads the meme library only when it asks, and keeps the answer by its length', async () => {
    await rolledBack(async (fixture) => {
      const { squad, checkIn } = fixture;
      let reads = 0;
      const memes: CoachMemes = () => {
        reads += 1;
        return Promise.resolve([
          { phrase: '对自己很好', meaning: '照顾自己', background: '小红书上流行' },
        ]);
      };
      const { agent, runs } = scriptedAgent((task) =>
        task.includes('发了动态') ? [{ tool: 'memes', input: {} }] : [],
      );
      await wakes(fixture, { agent, memes }).checkedIn({ checkIn, squads: [squad] });
      expect(reads).toBe(1);
      expect(runs[0]?.tools).toContain('memes');
      expect(runs[0]?.answers[0]).toBe('- 「对自己很好」：照顾自己（小红书上流行）');
      const report = await createPostgresCoachReport(fixture.trx).squad(squad);
      expect(report.wakes[0]?.steps[0]).toStrictEqual({
        tool: 'memes',
        input: {},
        output: '（22 字）',
      });
    });
  });

  it('gives the daily wake each member’s day: today’s plan, 饮食小目标 and yesterday’s posts', async () => {
    await rolledBack(async (fixture) => {
      const { squad, mia, leo } = fixture;
      const asked: unknown[] = [];
      const rest = { kind: 'rest' } as const;
      const memberFacts: CoachMemberFacts = (input) => {
        asked.push(input);
        return Promise.resolve([
          {
            member: mia,
            trainedDays: 50,
            healthyMeals: 0,
            cheatMeals: 0,
            disclaimers: 0,
            titles: 0,
            // Sunday, the wake's day, is the last.
            plan: [rest, rest, rest, rest, rest, rest, { kind: 'train', sport: '游泳' }],
            fuelGoals: ['喝够水'],
          },
        ]);
      };
      const { agent, runs } = scriptedAgent(() => []);
      const saturday = {
        id: randomUUID(),
        member: leo,
        day: '2026-10-31',
        createdAt: new Date('2026-10-31T20:00:00Z'),
        kind: 'healthyMeal' as const,
        text: '自己做的',
        postedTime: '22:05',
        reactedBy: [mia],
        comments: [],
      };
      await wakes(fixture, {
        agent,
        memberFacts,
        weeks: {
          [fixture.week.weekStart]: {
            ...fixture.week,
            checkIns: [saturday, ...fixture.week.checkIns],
          },
        },
      }).run();
      const daily = runs.find(({ task }) => task.includes('新的一天'));
      // Asked once for everyone it writes to (a reply's wake asks for its author alone).
      expect(asked.at(-1)).toStrictEqual({
        squad,
        members: [mia, leo],
        weekStart: fixture.week.weekStart,
      });
      expect(daily?.task).toContain('# 新的一天\n2026-11-01，周日。');
      expect(daily?.task).toContain(
        '### 米亚\n- 本周出赛表：周一休息，周二休息，周三休息，周四休息，周五休息，周六休息，周日游泳\n- 饮食小目标：喝够水\n- 这周练了：1 天\n- 这周发过：周日跑步\n',
      );
      // A member whose plan it couldn't read still gets a note.
      expect(daily?.task).toContain('### 队员2\n- 这周练了：0 天\n- 这周发过：周六健康餐\n');
      expect(daily?.task).toContain(
        '## 昨天（周六）小队的动态\n\n### 10-31 周六 · 队员2 · 健康餐\n- 发帖：本人当地 22:05\n- 写的：「自己做的」\n- 点了表情：米亚',
      );
    });
  });

  it('tells the daily wake each member’s weather, and writes the notes without it when it fails', async () => {
    await rolledBack(async (fixture) => {
      const { mia, leo } = fixture;
      const asked: unknown[] = [];
      const weatherOf: CoachWeather = (input) => {
        asked.push(input);
        // Only 米亚 shared where they are.
        return Promise.resolve(
          new Map([[mia, { words: '今天雨，8–13°C，降水概率 80%', city: '多伦多' }]]),
        );
      };
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, { agent, weatherOf }).run();
      const daily = runs.find(({ task }) => task.includes('新的一天'));
      expect(asked).toStrictEqual([{ members: [mia, leo], day: '2026-11-01' }]);
      expect(daily?.task).toContain(
        '### 米亚\n- 这周练了：1 天\n- 这周发过：周日跑步\n- 人在：多伦多\n- 当地天气：今天雨，8–13°C，降水概率 80%\n',
      );
      expect(daily?.task).toContain('### 队员2\n- 这周练了：0 天\n- 这周发过：还没发过\n');
    });
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, {
        agent,
        weatherOf: () => Promise.reject(new Error('no weather')),
      }).run();
      expect(runs.find(({ task }) => task.includes('新的一天'))?.task).toContain(
        '### 米亚\n- 这周练了：1 天\n- 这周发过：周日跑步\n- 用简体中文写。',
      );
    });
  });

  it('sets a day’s challenge on a note, gives a gift, and tells a check-in’s wake the answer', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, leo } = fixture;
      const given: unknown[] = [];
      const gifting: CoachGifting = {
        // 队员2 got one this week already; 米亚 has the cap.
        options: ({ members }) =>
          Promise.resolve({
            pool: [{ id: 'gift-scarf', description: '红围巾' }, { id: 'gift-cap' }],
            open: new Map(
              members.filter((each) => each === mia).map((each) => [each, ['gift-cap']]),
            ),
          }),
        given: () => Promise.resolve([]),
        give: (input) => {
          given.push(input);
          return Promise.resolve(undefined);
        },
      };
      const { agent, runs, picks } = scriptedAgent(
        (task) =>
          task.includes('新的一天')
            ? [
                { tool: 'note_to', input: { member: '米亚', text: '今天多喝水' } },
                { tool: 'note_to', input: { member: '队员2', text: '今天走走' } },
                { tool: 'give_gift', input: { member: '队员2', piece: 'gift-scarf', line: '冷' } },
                { tool: 'give_gift', input: { member: '米亚', piece: 'gift-cap', line: '戴上' } },
                { tool: 'give_gift', input: { member: '米亚', piece: 'gift-hat', line: '戴上' } },
                {
                  tool: 'give_gift',
                  input: { member: '米亚', piece: 'gift-scarf', line: '天冷了' },
                },
              ]
            : [],
        // The day's challenges, set before the notes: only 米亚 (米亚) gets one, by her name, and
        // the run asked again about 队员2 sets nothing.
        () => [
          {
            tool: 'set_challenge',
            input: {
              member: '米亚',
              recent: '这周练得少',
              needs: '补水',
              title: '喝水',
              amount: 0,
              unit: '杯',
              line: '天干',
            },
          },
          {
            tool: 'set_challenge',
            input: {
              member: '米亚',
              recent: '这周练得少',
              needs: '补水',
              title: '喝'.repeat(9),
              amount: 8,
              unit: '杯',
              line: '天干',
            },
          },
          {
            tool: 'set_challenge',
            input: {
              member: '米亚',
              recent: '这周练得少',
              needs: '补水',
              title: '喝水',
              amount: 8,
              unit: '杯',
              line: '天干，别等口渴',
            },
          },
          {
            tool: 'set_challenge',
            input: {
              member: '队员9',
              recent: '这周练得少',
              needs: '补水',
              title: '跑步',
              amount: 5,
              unit: '公里',
              line: '',
            },
          },
        ],
      );
      await wakes(fixture, { agent, gifting }).run();
      const daily = runs.find(({ task }) => task.includes('新的一天'));
      expect(daily?.tools).toContain('give_gift');
      expect(daily?.task).toContain('## 礼物清单\n- gift-scarf：红围巾\n- gift-cap');
      expect(daily?.task).toContain('## 这周还能收礼物的\n- 米亚（已有：gift-cap）');
      // Set on the challenge model, with only what makes a good challenge: the shared rules,
      // which open every coach's instructions, are for what it says.
      // Its own task, by name: no squad talk, no 队员N for a member with a nickname. Asked once
      // more about whom the first run left out.
      expect(picks).toHaveLength(2);
      const sharedRulesStart = daily?.instructions.split('\n')[0] ?? '';
      expect(sharedRulesStart).not.toBe('');
      expect(picks[0]?.instructions).not.toContain(sharedRulesStart);
      expect(picks[0]?.tools).toStrictEqual(['set_challenge', 'post_comments']);
      expect(picks[0]?.task).toMatch(/^今天是 \d{4}-\d{2}-\d{2}，周.。\n\n## 米亚\n- 今天的计划：/);
      expect(picks[0]?.task).toContain('\n\n## 队员2\n');
      expect(picks[0]?.task).not.toContain('# 新的一天');
      expect(picks[0]?.answers).toStrictEqual([
        '挑战不对：title 不超过 8 字，英文不超过 16 个字符；amount 是 1 到 9999 的整数；unit 不超过 4 字，英文不超过 8 个字符；line 不超过 24 字，英文不超过 48 个字符。',
        '挑战不对：title 不超过 8 字，英文不超过 16 个字符；amount 是 1 到 9999 的整数；unit 不超过 4 字，英文不超过 8 个字符；line 不超过 24 字，英文不超过 48 个字符。',
        '定好了：米亚「喝水 8 杯」。',
        '不能给 队员9 定挑战；能定的是：米亚、队员2。',
      ]);
      expect(picks[1]?.task).toContain(
        '\n\n## 还没定\n还没给队员2定挑战。请假或身体不舒服的不用给，其余的给他们定。',
      );
      expect(daily?.task).toContain(
        '## 今天的挑战（已经定好，单独一张卡给他）\n- 米亚「喝水 8 杯」，小字：天干，别等口渴',
      );
      expect(daily?.answers.slice(0, 6)).toStrictEqual([
        '便条写好了，给 米亚，下面附着挑战「喝水 8 杯」。',
        '便条写好了，给 队员2。',
        '队员2 这周不能收礼物；能收的是：米亚。',
        '米亚 已经有 gift-cap 了，换一件。',
        '没有 gift-hat 这件；能送的见任务里的礼物清单。',
        'gift-scarf 送给 米亚 了。',
      ]);
      expect(given).toStrictEqual([
        { squad, member: mia, coach: 'xiaohun', piece: 'gift-scarf', line: '天冷了' },
      ]);
      const notes = await sql<{ member_id: string; challenge_title: string | null }>`
        select member_id, challenge_title, challenge_amount, challenge_unit, challenge_line
        from public.coach_member_notes where squad_id = ${squad} order by member_id = ${mia} desc
      `.execute(trx);
      expect(notes.rows).toStrictEqual([
        {
          member_id: mia,
          challenge_title: '喝水',
          challenge_amount: 8,
          challenge_unit: '杯',
          challenge_line: '天干，别等口渴',
        },
        {
          member_id: leo,
          challenge_title: null,
          challenge_amount: null,
          challenge_unit: null,
          challenge_line: null,
        },
      ]);

      // The member accepts it (the first answer stands), and the next check-in's wake knows.
      const activity = createCoachActivity({ store: createPostgresCoachActivity(trx) });
      const [mine, theirs] = await sql<{ id: string }>`
        select id from public.coach_member_notes where squad_id = ${squad} order by member_id = ${mia} desc
      `
        .execute(trx)
        .then(({ rows }) => rows.map(({ id }) => Number(id)));
      // Answered only once the note reached them.
      const early = (note: number | undefined) =>
        activity.answerChallenge({
          squad,
          member: mia,
          note: note ?? 0,
          answer: 'accepted',
          today: '2026-11-01',
        });
      await expect(early(mine)).rejects.toThrow(CoachNoteNotFoundError);
      await sql`insert into public.coach_member_note_deliveries (note_id)
        select id from public.coach_member_notes where squad_id = ${squad}`.execute(trx);
      const answer = (
        member: string,
        { note, said }: { note: number | undefined; said: 'accepted' | 'declined' },
      ) =>
        activity.answerChallenge({
          squad,
          member,
          note: note ?? 0,
          answer: said,
          today: '2026-11-01',
        });
      // Not once its day is over (已过期).
      await expect(
        activity.answerChallenge({
          squad,
          member: mia,
          note: mine ?? 0,
          answer: 'accepted',
          today: '2026-11-02',
        }),
      ).rejects.toThrow(CoachChallengeDayOverError);
      expect(await answer(mia, { note: mine, said: 'accepted' })).toStrictEqual({
        answer: 'accepted',
      });
      expect(await answer(mia, { note: mine, said: 'declined' })).toStrictEqual({
        answer: 'accepted',
      });
      await expect(answer(leo, { note: mine, said: 'accepted' })).rejects.toThrow(
        CoachNoteNotFoundError,
      );
      await expect(answer(leo, { note: theirs, said: 'accepted' })).rejects.toThrow(
        CoachNoteNoChallengeError,
      );
      const later = randomUUID();
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${later}, ${mia}, '2026-11-01', ${now}, 'healthyMeal', '{"version": 1}')`.execute(
        trx,
      );
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: [
          ...fixture.week.checkIns,
          {
            id: later,
            member: mia,
            day: '2026-11-01',
            createdAt: now,
            kind: 'healthyMeal',
            reactedBy: [],
            comments: [],
          },
        ],
      };
      await wakes({ ...fixture, week }, { agent }).checkedIn({ checkIn: later, squads: [squad] });
      expect(runs.at(-1)?.task).toContain('\n- 今天的挑战：「喝水 8 杯」，接了，还没完成\n');
      // Only the member marks it done (我完成了): the coach has no way to.
      expect(runs.at(-1)?.tools).not.toContain('complete_challenge');
      const done = await sql<{ note_id: string }>`
        select note_id from public.coach_challenge_completions
        where note_id in (${String(mine)}, ${String(theirs)})`.execute(trx);
      expect(done.rows).toStrictEqual([]);
      await activity.completeChallenge({
        squad,
        member: mia,
        note: mine ?? 0,
        today: '2026-11-01',
      });
      // The next check-in's wake knows they did it.
      const again = randomUUID();
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${again}, ${mia}, '2026-11-01', ${now}, 'healthyMeal', '{"version": 1}')`.execute(
        trx,
      );
      await wakes(
        {
          ...fixture,
          week: {
            ...week,
            checkIns: [
              ...week.checkIns,
              {
                id: again,
                member: mia,
                day: '2026-11-01',
                createdAt: now,
                kind: 'healthyMeal',
                reactedBy: [],
                comments: [],
              },
            ],
          },
        },
        { agent },
      ).checkedIn({ checkIn: again, squads: [squad] });
      expect(runs.at(-1)?.task).toContain('\n- 今天的挑战：「喝水 8 杯」，已经完成了\n');
    });
  });

  it('reads yesterday from last week on a Monday, with only consented members’ posts', async () => {
    await rolledBack(async (fixture) => {
      const { mia, leo } = fixture;
      const { agent, runs } = scriptedAgent(() => []);
      const sunday = (member: string, text: string) => ({
        id: randomUUID(),
        member,
        day: '2026-11-01',
        createdAt: new Date('2026-11-01T20:00:00Z'),
        kind: 'healthyMeal' as const,
        text,
        reactedBy: [],
        comments: [],
      });
      // 10:00 in New York on Monday 2026-11-02, past the daily wake's hour.
      await wakes(fixture, {
        agent,
        at: new Date('2026-11-02T15:00:00Z'),
        consented: [mia],
        weeks: {
          '2026-10-26': {
            ...fixture.week,
            checkIns: [sunday(mia, '米亚的饭'), sunday(leo, '没同意的人')],
          },
          '2026-11-02': { weekStart: '2026-11-02', members: fixture.week.members, checkIns: [] },
        },
      }).run();
      const daily = runs.find(({ task }) => task.includes('# 新的一天\n2026-11-02'));
      expect(daily?.task).toContain(
        '## 昨天（周日）小队的动态\n\n### 11-01 周日 · 米亚 · 健康餐\n- 写的：「米亚的饭」',
      );
      expect(daily?.task).not.toContain('没同意的人');
      // Only the consented member gets a note.
      expect(daily?.task).toContain(
        '## 今天的便条（下面每人各写一张）\n\n### 米亚\n- 这周练了：0 天\n- 这周发过：还没发过\n',
      );
      expect(daily?.task).not.toContain('### 队员2');
    });
  });

  it('tells an @ about a post with photos that it hasn’t seen them', async () => {
    await rolledBack(async (fixture) => {
      const { squad, leo, checkIn } = fixture;
      const asked = await commentOn(fixture, {
        member: leo,
        text: '@小混 你看看我们吃了啥',
        at: new Date(now.getTime() + 60_000),
        mentionsCoach: 'xiaohun',
      });
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) =>
          each.id === checkIn
            ? { ...each, photos: ['m/a.jpg', 'm/b.jpg'], comments: [asked] }
            : each,
        ),
      };
      const hint = '\n- 照片 2 张，你还没看过（look_at_photos）\n';
      const seeing = scriptedAgent(() => []);
      await wakes(
        { ...fixture, week },
        {
          agent: seeing.agent,
          photoUrls: (paths) => Promise.resolve(paths.map((path) => `https://photos.test/${path}`)),
          at: new Date(now.getTime() + 2 * 60_000),
        },
      ).answer({ checkIn, comment: asked.id, coach: 'xiaohun', squads: [squad] });
      expect(seeing.runs[0]?.task).toContain(hint);
      expect(seeing.runs[0]?.tools).toContain('look_at_photos');
    });
  });

  it('has no photo tool for a check-in without photos', async () => {
    await rolledBack(async (fixture) => {
      const { squad, checkIn } = fixture;
      const { agent, runs } = scriptedAgent(() => []);
      await wakes(fixture, {
        agent,
        photoUrls: () => Promise.reject(new Error('never asked')),
      }).checkedIn({ checkIn, squads: [squad] });
      expect(runs[0]?.tools).not.toContain('look_at_photos');
    });
  });

  it('does not look at a check-in while coaching is off', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => []);
      await createCoachSettings({ store: createPostgresCoachSettings(fixture.trx) }).change(
        { coaching: false },
        MemberId.parse(fixture.mia),
      );
      await wakes(fixture, { agent }).checkedIn({
        checkIn: fixture.checkIn,
        squads: [fixture.squad],
      });
      expect(runs).toHaveLength(0);
    });
  });

  it('@s any teammate in a reply, by nickname, and tells the server whom', async () => {
    await rolledBack(async (fixture) => {
      const { leo } = fixture;
      const week: SquadWeek = {
        ...fixture.week,
        members: [
          fixture.week.members[0] ?? { member: fixture.mia },
          { member: leo, nickname: '小乐' },
        ],
      };
      const { agent, runs } = scriptedAgent((task) =>
        /^# .+发了动态/.test(task)
          ? [
              { tool: 'reply', input: { point: '接住', text: '一起跑', at: ['队员3'] } },
              // The post's author gets the reply anyway: never @'d.
              { tool: 'reply', input: { point: '接住', text: '一起跑', at: ['米亚', '小乐'] } },
            ]
          : [],
      );
      const told: Parameters<CoachReplied>[0][] = [];
      await wakes(
        { ...fixture, week },
        {
          agent,
          replied: (reply) => {
            told.push(reply);
            return Promise.resolve();
          },
        },
      ).run();
      expect(runs[0]?.answers).toStrictEqual(['不能 @ 队员3；能 @ 的是：米亚、小乐。', '已回复。']);
      expect(told).toMatchObject([{ author: fixture.mia, text: '@小乐 一起跑', mentions: [leo] }]);
      // Kept with the line, so the app can show the @ as a tag that opens 小乐's card.
      const checkIn = told[0]?.checkIn ?? '';
      const read = await createPostgresCoachActivity(fixture.trx).replies(fixture.squad, [checkIn]);
      expect(read).toMatchObject([{ checkIn, text: '@小乐 一起跑', mentions: [leo] }]);
    });
  });

  it('passes on what a member asks of the app, from them, with all they said there', async () => {
    await rolledBack(async (fixture) => {
      const { squad, mia, leo, checkIn } = fixture;
      const { agent, runs } = scriptedAgent((task) =>
        /^# .+发了动态/.test(task)
          ? [
              { tool: 'relay_feedback', input: { kind: 'idea', text: '' } },
              { tool: 'relay_feedback', input: { kind: 'problem', text: '照片传不上去' } },
              { tool: 'relay_feedback', input: { kind: 'idea', text: '想在动态上标地点' } },
              { tool: 'reply', input: { point: '接住', text: '帮你转给团队了' } },
            ]
          : task.includes('要回的这句')
            ? [{ tool: 'relay_feedback', input: { kind: 'idea', text: '想看全队的月度总结' } }]
            : [],
      );
      const relayed: Parameters<CoachFeedback>[0][] = [];
      const relayFeedback: CoachFeedback = (relay) => {
        relayed.push(relay);
        return Promise.resolve(undefined);
      };
      const post = '今天吃得很干净，要是能 tag 地点就好了';
      const withWords: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, text: post })),
      };
      await wakes({ ...fixture, week: withWords }, { agent, relayFeedback }).run();
      expect(runs[0]?.tools).toContain('relay_feedback');
      expect(runs[0]?.answers.slice(0, 3)).toStrictEqual([
        'text 是空的，写上他想要什么。',
        '会转给团队。',
        '已换成这条，会转给团队。',
      ]);
      // The daily wake has no one's words to pass on.
      expect(runs[1]?.tools).not.toContain('relay_feedback');
      // Each by the wake that passed it on, so a wake run twice passes it on once.
      expect(typeof relayed[0]?.wake).toBe('number');
      expect(relayed).toMatchObject([
        {
          squad,
          coach: 'xiaohun',
          member: mia,
          checkIn,
          kind: 'idea',
          text: '想在动态上标地点',
          quote: post,
        },
      ]);

      // Under a post, it is the reply's writer who asked, quoted in all they said there up to
      // the yes the wake answers: not the post's author's line, nor what came after.
      const wish = await commentOn(fixture, {
        member: leo,
        text: '要是能出个月度总结就好了',
        at: new Date(now.getTime() + 60_000),
      });
      const fromMia = await commentOn(fixture, {
        member: mia,
        text: '同意',
        at: new Date(now.getTime() + 90_000),
      });
      const yes = await commentOn(fixture, {
        member: leo,
        text: '@小混 帮我转给团队吧',
        at: new Date(now.getTime() + 120_000),
        mentionsCoach: 'xiaohun',
      });
      const later = await commentOn(fixture, {
        member: leo,
        text: '谢谢',
        at: new Date(now.getTime() + 150_000),
      });
      const withAsk: SquadWeek = {
        ...withWords,
        checkIns: withWords.checkIns.map((each) => ({
          ...each,
          comments: [wish, fromMia, yes, later],
        })),
      };
      await wakes(
        { ...fixture, week: withAsk },
        { agent, relayFeedback, at: new Date(now.getTime() + 3 * 60_000) },
      ).answer({ checkIn, comment: yes.id, coach: 'xiaohun', squads: [squad] });
      expect(relayed[1]).toMatchObject({
        squad,
        coach: 'xiaohun',
        member: leo,
        checkIn,
        comment: yes.id,
        kind: 'idea',
        text: '想看全队的月度总结',
        quote: '要是能出个月度总结就好了\n@小混 帮我转给团队吧',
      });
    });
  });

  it('offers nothing to pass on while passing feedback on is off', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => []);
      const asked: string[] = [];
      const withWords: SquadWeek = {
        ...fixture.week,
        checkIns: fixture.week.checkIns.map((each) => ({ ...each, text: '想要标地点' })),
      };
      await wakes(
        { ...fixture, week: withWords },
        {
          agent,
          relayingOn: (day) => {
            asked.push(day);
            return Promise.resolve(false);
          },
        },
      ).run();
      expect(/^# .+发了动态/.test(runs[0]?.task ?? '')).toBe(true);
      expect(runs[0]?.tools).not.toContain('relay_feedback');
      expect(asked).toStrictEqual(['2026-11-01']);
    });
  });

  it('has nothing to pass on from a post without words', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent((task) =>
        /^# .+发了动态/.test(task)
          ? [{ tool: 'relay_feedback', input: { kind: 'idea', text: '想标地点' } }]
          : [],
      );
      const relayed: Parameters<CoachFeedback>[0][] = [];
      await wakes(fixture, {
        agent,
        relayFeedback: (relay) => {
          relayed.push(relay);
          return Promise.resolve(undefined);
        },
      }).run();
      expect(runs[0]?.answers).toStrictEqual(['他在这里没写字，没有能转的。']);
      expect(relayed).toStrictEqual([]);
    });
  });

  it('dreams at night over yesterday: rewrites whole files, and only then', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, leo } = fixture;
      const { agent, runs } = scriptedAgent((task) =>
        task.startsWith('# 夜里')
          ? [
              { tool: 'rewrite_file', input: { path: 'notes.md', body: '不存在' } },
              { tool: 'rewrite_file', input: { path: 'memory.md', body: ' 队员2 周末爱跑步 \n' } },
              { tool: 'rewrite_file', input: { path: 'squad.md', body: '队名：squad' } },
            ]
          : [],
      );
      // Today: nothing from yesterday, so the night costs nothing.
      await wakes(fixture, { agent }).run();
      expect(runs.map(({ task }) => /^# .+发了动态/.test(task))).toStrictEqual([true, false]);
      expect(runs[1]?.task.startsWith('# 新的一天')).toBe(true);
      expect(runs[0]?.tools).not.toContain('rewrite_file');

      const tomorrow = new Date(now.getTime() + 86_400_000);
      await wakes(fixture, { agent, at: tomorrow }).run();
      const dream = runs[2];
      expect(dream?.task).toContain('## 过去七天（10-26 周一 到 11-01 周日）小队的动态');
      expect(dream?.task).toContain('## 和你的对话（过去七天，打卡下面，先后顺序）');
      expect(dream?.task).toContain('明天醒来你只记得它们。');
      expect(dream?.tools).toContain('rewrite_file');
      expect(dream?.tools).not.toContain('post_note');
      expect(dream?.tools).not.toContain('reply');
      expect(dream?.answers).toStrictEqual([
        '没有 notes.md 这个文件；能用的文件见任务里的列表。',
        '已重写 memory.md，现在 9 字。',
        '已重写 squad.md，现在 8 字。',
      ]);
      // The day's wake reads what the night left.
      expect(runs[3]?.task).toContain('### memory.md（你和大家之间的事）\n```\n队员2 周末爱跑步');
      const files = await sql<{ path: string; body: string }>`
        select distinct on (path) path, body from public.coach_files
        where squad_id = ${squad} order by path, id desc`.execute(trx);
      expect(files.rows).toStrictEqual([
        { path: 'memory.md', body: `{队员:${leo}} 周末爱跑步` },
        { path: 'squad.md', body: '队名：squad' },
      ]);
      const reasons = await sql<{ reason: string; state: string }>`
        select reason, state from public.coach_wakes where squad_id = ${squad} order by id`.execute(
        trx,
      );
      expect(reasons.rows).toStrictEqual([
        { reason: 'checkIn', state: 'done' },
        { reason: 'dream', state: 'done' },
        { reason: 'daily', state: 'done' },
        { reason: 'dream', state: 'done' },
        { reason: 'daily', state: 'done' },
      ]);
    });
  });

  it('dreams on its own model over the week before: posts, 战术板, notes and gifts', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, leo } = fixture;
      await createCoachSettings({ store: createPostgresCoachSettings(trx) }).change(
        { dreamModel: CoachModel.parse('openai/gpt-6-sol'), dreamReasoning: 'medium' },
        MemberId.parse(mia),
      );
      // A 战术板 line from Friday, written by an earlier wake.
      const stores = createPostgresCoachStores(trx);
      await stores.wakes.enqueue([{ squad, reason: { kind: 'daily', day: '2026-10-30' } }], now);
      const [earlier] = await stores.wakes.claim({ squads: [squad], limit: 1, now });
      if (earlier === undefined) throw new Error('no wake claimed');
      await stores.notes.save({
        squad,
        coach: CoachId.parse('xiaohun'),
        day: '2026-10-30',
        text: '周五去爬山',
        wake: earlier.id,
      });
      await stores.wakes.finish(earlier.id);
      // A post from Wednesday, five days before the night.
      const wednesday = randomUUID();
      const week: SquadWeek = {
        ...fixture.week,
        checkIns: [
          {
            id: wednesday,
            member: leo,
            day: '2026-10-28',
            createdAt: new Date('2026-10-28T12:00:00Z'),
            kind: 'trained',
            sport: '游泳',
            reactedBy: [],
            comments: [],
          },
          ...fixture.week.checkIns,
        ],
      };
      const gifting: CoachGifting = {
        options: () => Promise.resolve({ pool: [], open: new Map() }),
        given: ({ members }) =>
          Promise.resolve(
            members.includes(leo)
              ? [
                  {
                    member: leo,
                    piece: 'gift-scarf',
                    line: '冷了',
                    at: now,
                    opened: { worn: true },
                  },
                ]
              : [],
          ),
        give: () => Promise.resolve('no gifts in this test'),
      };
      const { agent, runs } = scriptedAgent(() => []);
      const tomorrow = new Date(now.getTime() + 86_400_000);
      await wakes({ ...fixture, week }, { agent, gifting, at: tomorrow }).run();
      const dream = runs.find(({ task }) => task.startsWith('# 夜里'));
      expect(dream).toMatchObject({ model: 'openai/gpt-6-sol', reasoning: 'medium' });
      expect(dream?.task).toContain('### 10-28 周三 · 队员2 · 训练：游泳');
      expect(dream?.task).toContain('## 你写的战术板（全队看得到）\n- 10-30 周五：「周五去爬山」');
      expect(dream?.task).toContain(
        '## 你送的礼物（只有收到的人知道）\n- 队员2：gift-scarf，你说「冷了」；拆开了，当场穿上了',
      );
      // The day's wakes keep the day's model.
      const daily = runs.find(({ task }) => task.startsWith('# 新的一天'));
      expect(daily).toMatchObject({ model: 'openai/gpt-6-luna', reasoning: 'low' });
    });
  });

  it('tells the night how yesterday’s challenges went, and why one was let go', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, leo } = fixture;
      const { agent, runs } = scriptedAgent(() => []);
      const noted = await sql<{ id: string; member_id: string }>`
        insert into public.coach_member_notes
          (squad_id, member_id, coach_id, day, text, challenge_title, challenge_amount, challenge_unit)
        values (${squad}, ${mia}, 'xiaohun', '2026-11-01', '多喝水', '喝水', 8, '杯'),
          (${squad}, ${leo}, 'xiaohun', '2026-11-01', '早餐加个蛋', '吃鸡蛋', null, null)
        returning id, member_id`.execute(trx);
      const noteOf = (member: string) =>
        noted.rows.find((row) => row.member_id === member)?.id ?? '';
      await sql`insert into public.coach_member_note_deliveries (note_id)
        select id from public.coach_member_notes where squad_id = ${squad}`.execute(trx);
      const activity = createCoachActivity({ store: createPostgresCoachActivity(trx) });
      await activity.answerChallenge({
        squad,
        member: leo,
        note: Number(noteOf(leo)),
        answer: 'declined',
        reason: '我鸡蛋过敏',
        today: '2026-11-01',
      });
      // A check-in's wake that day isn't told a challenge they let go (Leo) or never answered (Mia).
      const mealWake = async (member: string) => {
        const meal = randomUUID();
        await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
          values (${meal}, ${member}, '2026-11-01', ${now}, 'healthyMeal', '{"version": 1}')`.execute(
          trx,
        );
        await wakes(
          {
            ...fixture,
            week: {
              ...fixture.week,
              checkIns: [
                ...fixture.week.checkIns,
                {
                  id: meal,
                  member,
                  day: '2026-11-01',
                  createdAt: now,
                  kind: 'healthyMeal',
                  reactedBy: [],
                  comments: [],
                },
              ],
            },
          },
          { agent },
        ).checkedIn({ checkIn: meal, squads: [squad] });
        return runs.at(-1)?.task;
      };
      for (const member of [leo, mia]) {
        const task = await mealWake(member);
        expect(task).toMatch(/^# .+发了动态/);
        expect(task).not.toContain('今天的挑战');
      }
      await sql`insert into public.coach_challenge_completions (note_id, by)
        values (${noteOf(mia)}, 'member')`.execute(trx);
      await wakes(fixture, { agent, at: new Date(now.getTime() + 86_400_000) }).run();
      const dream = runs.find(({ task }) => task.startsWith('# 夜里'));
      // Each note, under whom it went to, with how its challenge went.
      expect(dream?.task).toContain(
        '## 你写的便条（只有收到的人看得到）\n\n### 米亚\n- 11-01 周日：「多喝水」\n  - 挑战「喝水 8 杯」：完成了\n\n### 队员2\n- 11-01 周日：「早餐加个蛋」\n  - 挑战「吃鸡蛋」：没接，理由：「我鸡蛋过敏」（只告诉了你）',
      );
    });
  });

  it('saves no new version of a file an edit left as it was', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad } = fixture;
      const { agent, runs } = scriptedAgent(() => [
        { tool: 'edit_file', input: { path: 'memory.md', find: '', replace: '跑' } },
        { tool: 'edit_file', input: { path: 'memory.md', find: '跑', replace: '' } },
      ]);
      expect(await wakes(fixture, { agent }).run()).toMatchObject({ done: 3 });
      expect(runs).toHaveLength(2);
      // Only the squad's file, started on the first wake.
      const files = await sql<{ path: string }>`
        select path from public.coach_files where squad_id = ${squad}`.execute(trx);
      expect(files.rows).toStrictEqual([{ path: 'squad.md' }]);
    });
  });

  it('sends the model only the words of members who agreed to AI use', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => [{ tool: 'squad_week', input: {} }]);
      // 米亚 hasn't agreed to the current copy: her check-in wakes no one, and her name and
      // run are nowhere the model reads.
      expect(await wakes(fixture, { agent, consented: [fixture.leo] }).run()).toMatchObject({
        queued: 2,
        done: 2,
      });
      expect(runs).toHaveLength(1);
      const read = [runs[0]?.task, ...(runs[0]?.answers ?? [])].join('\n');
      expect(read).toContain('队员1');
      expect(read).not.toContain('米亚');
      expect(read).not.toContain('跑步');
    });
  });

  it('shows a reply’s wake only the page of whom it answers, the day’s every page', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia, leo, checkIn } = fixture;
      // A third member, who has nothing to do with 米亚's check-in.
      const ann = randomUUID();
      await sql`insert into auth.users (id, email) values (${ann}, ${`${ann}@example.com`})`.execute(
        trx,
      );
      const week: SquadWeek = {
        ...fixture.week,
        members: [...fixture.week.members, { member: ann, nickname: '安' }],
      };
      // Each member has a page, written by an earlier wake.
      const stores = createPostgresCoachStores(trx);
      await stores.wakes.enqueue([{ squad, reason: { kind: 'dream', day: '2026-10-31' } }], now);
      const [earlier] = await stores.wakes.claim({ squads: [squad], limit: 1, now });
      if (earlier === undefined) throw new Error('no wake claimed');
      await stores.memory.save({
        squad,
        wake: earlier.id,
        files: [
          { path: `people/${mia}.md`, body: '爱跑步' },
          { path: `people/${leo}.md`, body: '怕下雨' },
          { path: `people/${ann}.md`, body: '昨晚吃了冰淇淋' },
        ],
      });
      await stores.wakes.finish(earlier.id);
      const { agent, runs } = scriptedAgent(() => []);
      await wakes({ ...fixture, week }, { agent }).run();
      // 米亚's check-in: her page alone, and everyone by name.
      const onCheckIn = runs.find(({ task }) => /^# .+发了动态/.test(task))?.task;
      expect(onCheckIn).toContain('- 你对米亚的了解（people/米亚.md）：\n```\n爱跑步\n```');
      expect(onCheckIn).not.toContain('怕下雨');
      expect(onCheckIn).not.toContain('冰淇淋');
      expect(onCheckIn).toContain('## 小队的人\n米亚、队员2、安。');
      // The day's wake is the squad's: every page.
      const daily = runs.find(({ task }) => task.startsWith('# 新的一天'))?.task;
      expect(daily).toContain('### people/安.md（安这个人）\n```\n昨晚吃了冰淇淋');
      // Leo @s the coach under it: his page is the one it reads, and the task says who asks.
      const asked = await commentOn(fixture, {
        member: leo,
        text: '下雨还跑吗',
        at: new Date(now.getTime() + 60_000),
        mentionsCoach: 'xiaohun',
      });
      const withComment: SquadWeek = {
        ...week,
        checkIns: week.checkIns.map((each) => ({ ...each, comments: [asked] })),
      };
      await wakes(
        { ...fixture, week: withComment },
        { agent, at: new Date(now.getTime() + 2 * 60_000) },
      ).answer({ checkIn, comment: asked.id, coach: 'xiaohun', squads: [squad] });
      const onReply = runs.find(({ task }) => task.includes('要回的这句'))?.task;
      expect(onReply).toContain('# 队员2在动态1下面 @ 你');
      expect(onReply).toContain('- 你对队员2的了解（people/队员2.md）：\n```\n怕下雨\n```');
      expect(onReply).not.toContain('爱跑步');
      expect(onReply).not.toContain('冰淇淋');
    });
  });

  it('writes the 战术板 in the squad’s language and a check-in’s reply in its author’s', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => []);
      const week: SquadWeek = {
        ...fixture.week,
        members: fixture.week.members.map((member) => ({ ...member, language: 'en' })),
        language: 'zh-Hant',
      };
      await wakes(fixture, { agent, weeks: { [week.weekStart]: week } }).run();
      const daily = runs.find(({ task }) => task.includes('新的一天'))?.task;
      const checkIn = runs.find(({ task }) => task.includes('发了动态'))?.task;
      expect(daily).toContain('## 战术板\n- 用繁體中文寫，照台灣的說法。');
      expect(checkIn?.split('\n\n')).toContain('## 他 App 的语言\nWrite in English.');
    });
  });

  it('wakes for a check-in made on a day already in next week, as a member far east has it', async () => {
    await rolledBack(async (fixture) => {
      const { agent, runs } = scriptedAgent(() => []);
      // 10am Sunday in New York is Monday in Tokyo: the check-in is in the week of 11-02.
      const nextWeek: SquadWeek = {
        ...fixture.week,
        weekStart: '2026-11-02',
        checkIns: fixture.week.checkIns.map((checkIn) => ({ ...checkIn, day: '2026-11-02' })),
      };
      expect(
        await wakes(fixture, { agent, weeks: { '2026-11-02': nextWeek } }).run(),
      ).toMatchObject({ queued: 3, done: 3 });
      // The day's wake was queued first, from this week; then the check-in's, from next week's.
      expect(runs.map(({ task }) => task.includes('米亚 · 训练：跑步'))).toStrictEqual([
        false,
        true,
      ]);
    });
  });

  it('counts the tokens of a wake whose check-in was deleted while it ran, and drops its reply', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, checkIn } = fixture;
      const agent: CoachAgent = {
        async run({ task, tools }) {
          if (!task.includes('新的一天')) {
            const use = (name: string, input: unknown) =>
              tools.find((tool) => tool.name === name)?.run(input);
            await use('reply', { text: '腿还在吗' });
            await use('react', { emoji: '💪' });
            await sql`delete from public.check_ins where id = ${checkIn}`.execute(trx);
          }
          return {
            ok: true,
            usage: { requests: 1, inputTokens: 1_000, cachedInputTokens: 0, outputTokens: 10 },
          };
        },
      };
      const told: unknown[] = [];
      const replied: CoachReplied = (reply) => {
        told.push(reply);
        return Promise.resolve();
      };
      expect(await wakes(fixture, { agent, replied }).run()).toMatchObject({ queued: 3, done: 3 });
      expect(told).toStrictEqual([]);
      // The check-in's, and the day's in two runs: its challenges, then its notes.
      expect(fixture.counted.runs.map(({ kind }) => kind)).toStrictEqual(['wake', 'wake', 'wake']);
      // The reply to a check-in that went is dropped, and the wake still ends.
      const replies =
        await sql`select 1 from public.coach_replies where squad_id = ${squad}`.execute(trx);
      expect(replies.rows).toHaveLength(0);
    });
  });

  it('runs a reply’s wake before the squad’s older ones, so its answer doesn’t wait', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, leo, checkIn } = fixture;
      const stores = createPostgresCoachStores(trx);
      await stores.wakes.enqueue([{ squad, reason: { kind: 'daily', day: '2026-11-01' } }], now);
      const reply = await commentOn(fixture, {
        member: leo,
        text: '教练',
        at: now,
        toCoach: 'xiaohun',
      });
      const later = new Date(now.getTime() + 60_000);
      await stores.wakes.enqueue(
        [{ squad, reason: { kind: 'comment', checkIn, comment: reply.id } }],
        later,
      );
      expect(await stores.wakes.claim({ squads: [squad], limit: 1, now: later })).toMatchObject([
        { reason: { kind: 'comment', comment: reply.id } },
      ]);
    });
  });

  it('runs a squad’s wakes one at a time, and keeps its files append-only until it ends', async () => {
    await rolledBack(async ({ trx, squad }) => {
      const stores = createPostgresCoachStores(trx);
      await stores.wakes.enqueue([{ squad, reason: { kind: 'daily', day: '2026-11-01' } }], now);
      const [wake] = await stores.wakes.claim({ squads: [squad], limit: 1, now });
      if (wake === undefined) throw new Error('no wake claimed');
      // While it runs, another run leaves the squad alone, so its wakes run in order.
      await stores.wakes.enqueue([{ squad, reason: { kind: 'daily', day: '2026-11-02' } }], now);
      expect(await stores.wakes.claim({ squads: [squad], limit: 1, now })).toStrictEqual([]);
      // Until it has run so long that it must have stopped: it is taken back first, alone.
      const later = new Date(now.getTime() + 16 * 60_000);
      expect(await stores.wakes.claim({ squads: [squad], limit: 5, now: later })).toMatchObject([
        { id: wake.id },
      ]);
      await stores.wakes.finish(wake.id);
      expect(await stores.wakes.claim({ squads: [squad], limit: 5, now: later })).toMatchObject([
        { reason: { kind: 'daily', day: '2026-11-02' } },
      ]);
      await stores.memory.save({ squad, wake: wake.id, files: [{ path: 'memory.md', body: 'a' }] });
      await sql`savepoint attempt`.execute(trx);
      await expect(
        sql`update public.coach_files set body = 'b' where squad_id = ${squad}`.execute(trx),
      ).rejects.toThrow('coach_files is append-only');
      await sql`rollback to savepoint attempt`.execute(trx);
      // The wake may go (its check-in did), and the file keeps its body.
      await sql`delete from public.coach_wakes where id = ${wake.id}`.execute(trx);
      expect((await stores.memory.files(squad)).get('memory.md')).toBe('a');
      await sql`delete from public.squads where id = ${squad}`.execute(trx);
      expect((await stores.memory.files(squad)).size).toBe(0);
    });
  });
  it('previews a member’s day without saving or sending anything but its tokens', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      const given: unknown[] = [];
      const gifting: CoachGifting = {
        options: ({ members }) =>
          Promise.resolve({
            pool: [{ id: 'gift-scarf', description: '红围巾' }],
            open: new Map(members.map((each) => [each, []])),
          }),
        given: () => Promise.resolve([]),
        give: (input) => {
          given.push(input);
          return Promise.resolve(undefined);
        },
      };
      const { agent, runs } = scriptedAgent(
        () => [
          { tool: 'post_note', input: { text: '周日歇好' } },
          { tool: 'note_to', input: { member: '米亚', text: '今天多喝水' } },
          // Only the member previewed gets a note or a gift.
          { tool: 'note_to', input: { member: '队员2', text: '走走' } },
          { tool: 'give_gift', input: { member: '米亚', piece: 'gift-scarf', line: '天冷了' } },
          { tool: 'remember', input: { path: 'people/米亚.md', fact: '米亚爱喝水' } },
        ],
        water,
      );
      const preview = await wakes(fixture, { agent, gifting }).preview({ squad, member: mia });
      expect(runs).toHaveLength(1);
      expect(runs[0]?.answers).toStrictEqual([
        '已写上战术板。',
        '便条写好了，给 米亚，下面附着挑战「喝水 8 杯」。',
        '不能给 队员2 写便条；能写的是：米亚。',
        'gift-scarf 送给 米亚 了。',
        '记下了，在 people/米亚.md。',
      ]);
      expect(runs[0]?.task).toContain('## 今天的便条（下面每人各写一张）');
      expect(preview).toMatchObject({
        ran: true,
        day: '2026-11-01',
        board: '周日歇好',
        note: {
          text: '今天多喝水',
          challenge: { title: '喝水', amount: 8, unit: '杯', line: '天干' },
        },
        gift: { piece: 'gift-scarf', line: '天冷了' },
        // Setting the challenge and writing the notes.
        costMicros: 9200,
      });
      expect(preview.ran && preview.files.map(({ path }) => path)).toContain(`people/${mia}.md`);
      expect(given).toStrictEqual([]);
      const saved = await sql<{ notes: string; board: string; wakes: string }>`
        select
          (select count(*) from public.coach_member_notes where squad_id = ${squad}) as notes,
          (select count(*) from public.coach_notes where squad_id = ${squad}) as board,
          (select count(*) from public.coach_wakes where squad_id = ${squad}) as wakes
      `.execute(trx);
      expect(saved.rows).toStrictEqual([{ notes: '0', board: '0', wakes: '0' }]);
      // Its tokens are counted all the same, as a preview, to the squad: an admin asked for it.
      expect(
        fixture.counted.runs.map(({ kind, member, costMicros }) => ({ kind, member, costMicros })),
      ).toStrictEqual([
        { kind: 'preview', member: undefined, costMicros: 4600 },
        { kind: 'preview', member: undefined, costMicros: 4600 },
      ]);
      expect(
        await wakes(fixture, { agent, gifting }).preview({ squad, member: randomUUID() }),
      ).toStrictEqual({
        ran: false,
        why: 'the member is not in the squad',
      });
    });
  });
  it('delivers a previewed note to the member alone each time asked, the newest the day’s', async () => {
    await rolledBack(async (fixture) => {
      const { trx, squad, mia } = fixture;
      const { agent } = scriptedAgent(
        () => [
          { tool: 'post_note', input: { text: '周日歇好' } },
          { tool: 'note_to', input: { member: '米亚', text: '今天多喝水' } },
        ],
        water,
      );
      const first = await wakes(fixture, { agent }).preview({ squad, member: mia, deliver: true });
      expect(first).toMatchObject({ ran: true, delivered: true, note: { text: '今天多喝水' } });
      const saved = await sql<{ member: string; text: string; title: string; board: string }>`
        select m.member_id as member, m.text, m.challenge_title as title,
          (select count(*) from public.coach_notes where squad_id = ${squad}) as board
        from public.coach_member_notes m where m.squad_id = ${squad}
      `.execute(trx);
      expect(saved.rows).toStrictEqual([
        { member: mia, text: '今天多喝水', title: '喝水', board: '0' },
      ]);
      const again = await wakes(fixture, { agent }).preview({ squad, member: mia, deliver: true });
      expect(again).toMatchObject({ ran: true, delivered: true });
      const notes = await sql<{ id: string }>`
        select id from public.coach_member_notes where squad_id = ${squad} and member_id = ${mia}
        order by id
      `.execute(trx);
      expect(notes.rows).toHaveLength(2);
      // Once both reached her, the newest note's challenge is the day's.
      const delivery = createPostgresCoachNoteDelivery(trx);
      for (const { id } of notes.rows) await delivery.delivered(Number(id));
      const stores = createPostgresCoachStores(trx);
      const day = first.ran ? first.day : '';
      expect(await stores.memberNotes.challengeOf({ squad, member: mia, day })).toMatchObject({
        note: Number(notes.rows[1]?.id),
      });
      expect(await stores.memberNotes.challengesOn({ squad, day })).toMatchObject([
        { member: mia, note: Number(notes.rows[1]?.id) },
      ]);
      // A later note without a challenge hides none.
      await stores.memberNotes.save({
        squad,
        member: mia,
        coach: CoachId.parse('xiaohun'),
        day,
        text: '早点睡',
      });
      const plainNote = await sql<{ id: string }>`
        select max(id) as id from public.coach_member_notes where member_id = ${mia}
      `.execute(trx);
      await delivery.delivered(Number(plainNote.rows[0]?.id));
      expect(await stores.memberNotes.challengeOf({ squad, member: mia, day })).toMatchObject({
        note: Number(notes.rows[1]?.id),
      });
      const plain = await wakes(fixture, { agent }).preview({ squad, member: mia });
      expect(plain.ran && 'delivered' in plain).toBe(false);
    });
  });
});
