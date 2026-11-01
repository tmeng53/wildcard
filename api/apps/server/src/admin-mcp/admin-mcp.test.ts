import { randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';

import { serve, type ServerType } from '@hono/node-server';
import {
  Client,
  StreamableHTTPClientTransport,
  UnauthorizedError,
  type OAuthClientProvider,
  type OAuthClientInformation,
  type StoredOAuthTokens,
} from '@modelcontextprotocol/client';
import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeekSummaryWords,
  createPostgresWeeklyPlanStore,
  createWeekSummaryWords,
  createWeeklyPlans,
} from '@wildcard/check-ins';
import { createDailyPushSettings, createPostgresDailyPushSettings } from '@wildcard/push';
import {
  createDiceLines,
  createDraftSettings,
  createPostgresDiceLines,
  createPostgresDraftSettings,
} from '@wildcard/disclaimer-drafts';
import {
  createCoachCatalog,
  createCoachHiring,
  createCoachSettings,
  createPostgresCoachCatalog,
  createPostgresCoachHiring,
  createPostgresCoachReport,
  createPostgresCoachSettings,
} from '@wildcard/coach';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createMemes, createPostgresMemeStore } from '@wildcard/memes';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { createAwardSettings, createPostgresAwardSettings } from '@wildcard/weekly-awards';
import { sql } from 'kysely';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseOAuthConsent } from '../adapters/supabase-oauth-consent.js';
import { createSupabaseAccounts, createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createApp } from '../app.js';
import { createLog } from '../log.js';
import {
  adminOn,
  aiConsentOn,
  config,
  noJobs,
  nudgesOn,
  pushOn,
  signUp,
} from '../test-kit/local-supabase.js';
import { adminTool } from './admin-tool.js';
import { listAdminLog } from './tools/admin-log.js';
import { aiWritingTools } from './tools/ai-writing.js';
import { dailyPushTools } from './tools/daily-push.js';
import { disclaimerDiceTools } from './tools/disclaimer-dice.js';
import { memeTools } from './tools/memes.js';
import { coachTools } from './tools/coach.js';
import { sportTools } from './tools/sports.js';
import { weekSummaryWordTools } from './tools/week-summary-words.js';
import { catalogOn, unlimitedPublicRoutes } from '../test-kit/public-routes.js';
import { unusedWeeklyAwards, unusedWeekSummaryWords } from '../test-kit/weekly-awards.js';

// The admin MCP server as an MCP client meets it: the API listens on a real port, the client
// (the official MCP SDK) discovers how to sign in from the 401, signs in through local Supabase
// Auth's OAuth 2.1 server as a client registered by hand, and the admin approves it on our
// consent page.

const db = createDatabase(config.databaseUrl);
const publishableKey = z.string().min(1).parse(process.env.SUPABASE_PUBLISHABLE_KEY);
let server: ServerType;
let mcpUrl: URL;

beforeAll(async () => {
  registered = await registerClient();
  const port = await new Promise<number>((resolve) => {
    // Listen first: the server names itself by its URL, which needs the port.
    let app: ReturnType<typeof createApp> | undefined;
    server = serve(
      {
        fetch: (request) => (app ? app.fetch(request) : new Response(null, { status: 503 })),
        port: 0,
      },
      (info: AddressInfo) => {
        const publicUrl = new URL(`http://localhost:${String(info.port)}`);
        const admin = adminOn();
        const photos = {
          createUploadUrl: unused,
          exists: unused,
          createViewUrls: unused,
          deleteAllOf: unused,
        };
        app = createApp({
          db,
          verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
          accounts: createSupabaseAccounts({
            supabaseUrl: config.supabaseUrl,
            secretKey: config.supabaseSecretKey,
          }),
          revokeAppleSignIn: undefined,
          catalog: catalogOn(db),
          publicRoutes: unlimitedPublicRoutes,
          checkIns: createCheckIns({
            sports: createSports({ store: createPostgresSportStore(db) }),
            store: createPostgresCheckInStore(db),
            membership: createSquads({
              store: createPostgresSquadStore(db),
              inviteCodes: randomInviteCodes,
              aiConsent: () => Promise.resolve(true),
            }),
            reactions: createPostgresReactionStore(db),
            comments: createPostgresCommentStore(db),
            photos,
            plans: createPostgresWeeklyPlanStore(db),
            calendarOf: () => Promise.resolve(undefined),
            clock: () => new Date(),
          }),
          weeklyPlans: createWeeklyPlans({
            sports: createSports({ store: createPostgresSportStore(db) }),
            store: createPostgresWeeklyPlanStore(db),
            calendarOf: () => Promise.resolve(undefined),
            clock: () => new Date(),
          }),
          members: createMembers({ store: createPostgresProfileStore(db) }),
          squads: createSquads({
            store: createPostgresSquadStore(db),
            inviteCodes: randomInviteCodes,
            aiConsent: () => Promise.resolve(true),
          }),
          disclaimerDrafts: { write: () => Promise.reject(new Error('unused')) },
          push: pushOn(db),
          photos,
          aiConsent: aiConsentOn(db),
          nudges: nudgesOn(db),
          weeklyAwards: unusedWeeklyAwards,
          weekSummaryWords: unusedWeekSummaryWords,
          log: createLog(() => undefined),
          jobs: noJobs,
          admin: {
            ...admin,
            // Writing the log fails for a meme marked so, as a dropped connection would.
            admins: (scope) => {
              const admins = admin.admins(scope);
              return {
                ...admins,
                logChange: (entry) =>
                  String(entry.arguments.phrase).startsWith(logFails)
                    ? Promise.reject(new Error('the log is unreachable'))
                    : admins.logChange(entry),
              };
            },
            publicUrl,
            consent: createSupabaseOAuthConsent({
              supabaseUrl: config.supabaseUrl,
              secretKey: config.supabaseSecretKey,
            }),
            tools: (scope) => [
              listAdminLog({ admins: admin.admins(scope) }),
              ...memeTools({
                memes: createMemes({ store: createPostgresMemeStore(scope), clock: () => now }),
                clock: () => now,
              }),
              ...aiWritingTools({
                drafts: createDraftSettings({ store: createPostgresDraftSettings(scope) }),
                awards: createAwardSettings({ store: createPostgresAwardSettings(scope) }),
              }),
              ...disclaimerDiceTools({
                dice: createDiceLines({ store: createPostgresDiceLines(scope) }),
              }),
              ...dailyPushTools({
                settings: createDailyPushSettings({
                  store: createPostgresDailyPushSettings(scope),
                }),
              }),
              ...weekSummaryWordTools({
                words: createWeekSummaryWords({ store: createPostgresWeekSummaryWords(scope) }),
              }),
              ...sportTools({ sports: createSports({ store: createPostgresSportStore(scope) }) }),
              ...coachTools({
                settings: createCoachSettings({ store: createPostgresCoachSettings(scope) }),
                coaches: createCoachCatalog({ store: createPostgresCoachCatalog(scope) }),
                hiring: createCoachHiring({
                  hiring: createPostgresCoachHiring(scope),
                  catalog: createPostgresCoachCatalog(scope),
                }),
                report: createPostgresCoachReport(scope),
                clock: () => new Date(),
              }),
              // A tool that changes something, standing in for the meme tools.
              adminTool({
                name: 'rename_thing',
                title: 'Rename a thing',
                description: 'Renames a thing.',
                changes: true,
                input: z.strictObject({ name: z.string() }),
                run: ({ name }) => Promise.resolve({ version: 1, renamed: name }),
              }),
            ],
          },
        });
        resolve(info.port);
      },
    );
  });
  mcpUrl = new URL(`http://localhost:${String(port)}/mcp`);
});
afterAll(async () => {
  server.close();
  await db.destroy();
});

const now = new Date('2026-10-19T16:00:00.000Z');
const logFails = '日志断了';
const unused = () => Promise.reject(new Error('the admin tools use no photos'));

/** A member signed up through local Supabase Auth, on the admin list when asked. */
async function member(options: { admin: boolean }) {
  const signedUp = await signUp();
  if (options.admin) {
    await sql`insert into public.admins (member_id) values (${signedUp.userId})`.execute(db);
  }
  return signedUp;
}

const clientMetadata = {
  client_name: 'Admin MCP test',
  redirect_uris: ['http://localhost:9999/callback'],
  token_endpoint_auth_method: 'none',
  grant_types: ['authorization_code', 'refresh_token'],
  response_types: ['code'],
};

/** Registers the MCP client by hand, as an admin does for Claude Code or claude.ai. */
async function registerClient(): Promise<OAuthClientInformation> {
  const response = await fetch(`${config.supabaseUrl}/auth/v1/admin/oauth/clients`, {
    method: 'POST',
    headers: {
      apikey: config.supabaseSecretKey,
      authorization: `Bearer ${config.supabaseSecretKey}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(clientMetadata),
  });
  return { client_id: z.object({ client_id: z.uuid() }).parse(await response.json()).client_id };
}
let registered: OAuthClientInformation;

/**
 * An MCP client's OAuth state, kept in memory. "Opening the browser" approves the request as
 * the member: on our consent page, as an admin does, or straight through Supabase Auth's API
 * with the member's app session, as someone holding a stolen session could.
 */
function clientSignedInAs(
  member: { readonly token: string; readonly email: string; readonly password: string },
  options: { readonly approveThrough: 'consent page' | 'auth API' } = {
    approveThrough: 'consent page',
  },
): OAuthClientProvider & { readonly code: () => string } {
  let tokens: StoredOAuthTokens | undefined;
  let verifier = '';
  let code = '';
  const approve = async (id: string): Promise<URL> => {
    if (options.approveThrough === 'consent page') {
      const form = (fields: Record<string, string>) => ({
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ authorization_id: id, ...fields }).toString(),
        redirect: 'manual' as const,
      });
      const consentPage = new URL('/oauth/consent/', mcpUrl);
      const signedIn = await fetch(
        new URL('sign-in', consentPage),
        form({ email: member.email, password: member.password }),
      );
      const cookie = signedIn.headers.getSetCookie().map((each) => each.split(';')[0]);
      const request = form({ answer: 'approve' });
      const approved = await fetch(new URL('answer', consentPage), {
        ...request,
        headers: { ...request.headers, cookie: cookie.join('; ') },
      });
      return new URL(z.string().parse(approved.headers.get('location')));
    }
    const authorizations = `${config.supabaseUrl}/auth/v1/oauth/authorizations/${id}`;
    const authHeaders = { apikey: publishableKey, authorization: `Bearer ${member.token}` };
    await fetch(authorizations, { headers: authHeaders });
    const approved = await fetch(`${authorizations}/consent`, {
      method: 'POST',
      headers: { ...authHeaders, 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'approve' }),
    });
    return new URL(z.object({ redirect_url: z.url() }).parse(await approved.json()).redirect_url);
  };
  return {
    redirectUrl: clientMetadata.redirect_uris[0],
    clientMetadata,
    // Registered by hand; with no saveClientInformation the client can't register itself.
    clientInformation: () => registered,
    tokens: () => tokens,
    saveTokens: (saved) => {
      tokens = saved;
    },
    saveCodeVerifier: (saved) => {
      verifier = saved;
    },
    codeVerifier: () => verifier,
    redirectToAuthorization: async (authorizationUrl) => {
      const redirect = await fetch(authorizationUrl, { redirect: 'manual' });
      const consentUrl = new URL(z.string().parse(redirect.headers.get('location')));
      const id = z.string().parse(consentUrl.searchParams.get('authorization_id'));
      code = z.string().parse((await approve(id)).searchParams.get('code'));
    },
    code: () => code,
  };
}

/** Connects an MCP client, signing in through OAuth the first time, as Claude Code does. */
async function connect(provider: ReturnType<typeof clientSignedInAs>) {
  const client = new Client({ name: 'admin-mcp-test', version: '1.0.0' });
  const first = new StreamableHTTPClientTransport(mcpUrl, { authProvider: provider });
  await expect(client.connect(first)).rejects.toThrow(UnauthorizedError);
  await first.finishAuth(provider.code());
  const signedIn = new StreamableHTTPClientTransport(mcpUrl, { authProvider: provider });
  await client.connect(signedIn);
  return client;
}

const textOf = (result: unknown) =>
  z
    .object({ content: z.tuple([z.object({ type: z.literal('text'), text: z.string() })]) })
    .parse(result).content[0].text;

describe('the admin MCP server', () => {
  it('signs an admin in through OAuth and lists its tools', async () => {
    const client = await connect(clientSignedInAs(await member({ admin: true })));
    const { tools } = await client.listTools();
    expect(tools.map(({ name, annotations }) => [name, annotations?.readOnlyHint])).toStrictEqual([
      ['list_admin_log', true],
      ['list_memes', true],
      ['add_memes', false],
      ['turn_off_meme', false],
      ['turn_on_meme', false],
      ['get_disclaimer_draft_settings', true],
      ['change_disclaimer_draft_settings', false],
      ['get_weekly_award_settings', true],
      ['change_weekly_award_settings', false],
      ['get_disclaimer_dice', true],
      ['change_disclaimer_dice', false],
      ['get_daily_push_settings', true],
      ['change_daily_push_settings', false],
      ['get_week_summary_words', true],
      ['change_week_summary_words', false],
      ['get_sports', true],
      ['put_sport', false],
      ['put_sport_category', false],
      ['set_sport_picks', false],
      ['get_coach_settings', true],
      ['change_coach_settings', false],
      ['list_coaches', true],
      ['put_coach', false],
      ['hire_coach', false],
      ['fire_coach', false],
      ['get_squad_coaching', true],
      ['rename_thing', false],
    ]);
    await client.close();
  });

  it('logs a change and lists it back, while reads are not logged', async () => {
    const admin = await member({ admin: true });
    const client = await connect(clientSignedInAs(admin));

    const renamed = await client.callTool({
      name: 'rename_thing',
      arguments: { name: '早八跑团' },
    });
    expect(JSON.parse(textOf(renamed))).toStrictEqual({ version: 1, renamed: '早八跑团' });
    await client.callTool({ name: 'list_admin_log', arguments: {} });

    const rows = await sql<{ at: Date; action: unknown }>`
      select at, action from public.admin_actions where admin_id = ${admin.userId}
    `.execute(db);
    expect(rows.rows.map(({ action }) => action)).toStrictEqual([
      { version: 1, tool: 'rename_thing', arguments: { name: '早八跑团' } },
    ]);
    const listed = await client.callTool({ name: 'list_admin_log', arguments: {} });
    expect(JSON.parse(textOf(listed))).toStrictEqual({
      version: 1,
      changes: [
        {
          at: rows.rows[0]?.at.toISOString(),
          tool: 'rename_thing',
          arguments: { name: '早八跑团' },
        },
      ],
    });
    await client.close();
  });

  it('adds memes, turns one off and back on, and logs each change', async () => {
    const admin = await member({ admin: true });
    const client = await connect(clientSignedInAs(admin));
    const meme = (name: string) => ({
      phrase: `${name}${randomUUID().slice(0, 8)}`,
      background: '2024 年一个外国博主在中国街头问路人「city不city啊」，口音魔性，迅速走红。',
      meaning: '问某事洋不洋气、时髦不时髦。',
      styles: ['funny'],
      source: '抖音',
    });
    const city = meme('city不city');
    const banwei = meme('班味');
    const call = async (name: string, args: Record<string, unknown>) =>
      z.json().parse(JSON.parse(textOf(await client.callTool({ name, arguments: args }))));
    const inUse = async () => {
      const { memes } = z
        .object({ memes: z.array(z.object({ phrase: z.string() }).loose()) })
        .parse(await call('list_memes', {}));
      return memes.filter(({ phrase }) => [city.phrase, banwei.phrase].includes(phrase));
    };

    // An approved.json batch, with its approval time; a meme approved now needs none.
    expect(
      await call('add_memes', { memes: [city], approvedAt: '2026-10-18T17:00:00Z' }),
    ).toStrictEqual({ version: 1, added: [city.phrase], alreadyThere: [] });
    expect(await call('add_memes', { memes: [city, banwei] })).toStrictEqual({
      version: 1,
      added: [banwei.phrase],
      alreadyThere: [city.phrase],
    });
    expect(await inUse()).toStrictEqual([
      { ...banwei, approvedAt: '2026-10-19T16:00:00.000Z' },
      { ...city, approvedAt: '2026-10-18T17:00:00.000Z' },
    ]);

    expect(await call('turn_off_meme', { phrase: city.phrase })).toStrictEqual({
      version: 1,
      turnedOff: city.phrase,
    });
    expect((await inUse()).map(({ phrase }) => phrase)).toStrictEqual([banwei.phrase]);
    expect(await call('turn_on_meme', { phrase: city.phrase })).toStrictEqual({
      version: 1,
      turnedOn: city.phrase,
    });
    expect((await inUse()).map(({ phrase }) => phrase)).toStrictEqual([banwei.phrase, city.phrase]);

    const missing = await client.callTool({
      name: 'turn_off_meme',
      arguments: { phrase: '没这个梗' },
    });
    expect([missing.isError, textOf(missing)]).toStrictEqual([
      true,
      'MEME_NOT_FOUND: The meme library has no 「没这个梗」.',
    ]);

    const rows = await sql<{ action: { tool: string } }>`
      select action from public.admin_actions where admin_id = ${admin.userId} order by id
    `.execute(db);
    expect(rows.rows.map(({ action }) => action.tool)).toStrictEqual([
      'add_memes',
      'add_memes',
      'turn_off_meme',
      'turn_on_meme',
    ]);
    await client.close();
  });

  it('reads and changes what the AI writes with, logging each change once', async () => {
    const admin = await member({ admin: true });
    const client = await connect(clientSignedInAs(admin));
    const call = async (name: string, args: Record<string, unknown> = {}) => {
      const result = await client.callTool({ name, arguments: args });
      return { isError: result.isError === true, text: textOf(result) };
    };
    const read = async (name: string) =>
      z.record(z.string(), z.json()).parse(JSON.parse((await call(name)).text));
    const drafts = await read('get_disclaimer_draft_settings');
    const awards = await read('get_weekly_award_settings');
    expect(drafts).toMatchObject({
      version: 1,
      writing: true,
      model: 'openai/gpt-6-luna',
      batchesPerDay: 6,
      memeChance: 0.3,
    });
    expect(awards).toMatchObject({ version: 1, model: 'openai/gpt-6-luna' });
    const events = async (
      table: 'disclaimer_draft_setting_events' | 'weekly_award_setting_events',
    ) =>
      (
        await sql<{ settings: unknown }>`
          select settings from ${sql.table(table)} where changed_by = ${admin.userId} order by id
        `.execute(db)
      ).rows.map(({ settings }) => settings);

    try {
      const changed = await call('change_disclaimer_draft_settings', {
        model: 'anthropic/claude-haiku-5-5',
        batchesPerDay: 7,
        // Not exact in a 4-byte float: the row and its log must still agree.
        memeChance: 0.15,
      });
      const expected = {
        ...drafts,
        model: 'anthropic/claude-haiku-5-5',
        batchesPerDay: 7,
        memeChance: 0.15,
      };
      expect(JSON.parse(changed.text)).toStrictEqual(expected);
      expect(await read('get_disclaimer_draft_settings')).toStrictEqual(expected);
      // The same change again saves nothing new.
      await call('change_disclaimer_draft_settings', { batchesPerDay: 7, memeChance: 0.15 });
      expect(await events('disclaimer_draft_setting_events')).toStrictEqual([expected]);

      // Two admins at once, each changing one thing: both changes stand.
      await Promise.all([
        call('change_disclaimer_draft_settings', { batchesPerDay: 8 }),
        call('change_disclaimer_draft_settings', { writing: false }),
      ]);
      expect(await read('get_disclaimer_draft_settings')).toMatchObject({
        batchesPerDay: 8,
        writing: false,
      });

      const moved = await call('change_weekly_award_settings', {
        moves: { pump: '握拳，跳起来' },
      });
      expect(JSON.parse(moved.text)).toStrictEqual({
        ...awards,
        moves: { ...z.record(z.string(), z.string()).parse(awards.moves), pump: '握拳，跳起来' },
      });

      // A provider the server doesn't know, a move the app doesn't have, or no change at all.
      for (const [name, args] of [
        ['change_disclaimer_draft_settings', { model: 'gemini/flash' }],
        ['change_disclaimer_draft_settings', { memeChance: 2 }],
        ['change_disclaimer_draft_settings', {}],
        ['change_weekly_award_settings', { moves: { moonwalk: '太空步' } }],
      ] as const) {
        expect((await call(name, args)).isError).toBe(true);
      }
      expect(await events('weekly_award_setting_events')).toHaveLength(1);
    } finally {
      await call('change_disclaimer_draft_settings', {
        writing: drafts.writing,
        model: drafts.model,
        batchesPerDay: drafts.batchesPerDay,
        memeChance: drafts.memeChance,
      });
      await call('change_weekly_award_settings', { moves: awards.moves });
    }
    expect(await read('get_disclaimer_draft_settings')).toStrictEqual(drafts);
    expect(await read('get_weekly_award_settings')).toStrictEqual(awards);
    await client.close();
  });

  it('reads and changes the coach settings and the coaches, logging each change', async () => {
    const admin = await member({ admin: true });
    const client = await connect(clientSignedInAs(admin));
    const call = async (name: string, args: Record<string, unknown> = {}) => {
      const result = await client.callTool({ name, arguments: args });
      return { isError: result.isError === true, text: textOf(result) };
    };
    const read = async (name: string) =>
      z.record(z.string(), z.json()).parse(JSON.parse((await call(name)).text));
    const Coaches = z.object({ coaches: z.array(z.record(z.string(), z.json())) });
    const settings = await read('get_coach_settings');
    expect(settings).toMatchObject({ version: 1, coaching: false, model: 'openai/gpt-6-luna' });
    const listed = Coaches.parse(await read('list_coaches')).coaches;
    const xiaohun = listed.find(({ id }) => id === 'xiaohun');
    expect(xiaohun).toMatchObject({ id: 'xiaohun', name: '小混', offered: true });
    const edit = Object.fromEntries(
      Object.entries(z.record(z.string(), z.json()).parse(xiaohun)).filter(
        ([key]) => key !== 'version',
      ),
    );
    const squad = randomUUID();
    await sql`insert into public.squads (id, name, invite_code) values (${squad}, 'squad', ${squad})`.execute(
      db,
    );

    try {
      const on = await call('change_coach_settings', { coaching: true });
      expect(JSON.parse(on.text)).toStrictEqual({ ...settings, coaching: true });

      // A squad hires one coach at a time, and fires it before hiring another.
      const nothing = { wakes: 0, requests: 0, inputTokens: 0, outputTokens: 0, costMicros: 0 };
      const coaching = async () =>
        z.json().parse(JSON.parse((await call('get_squad_coaching', { squad })).text));
      expect(await coaching()).toStrictEqual({
        version: 1,
        coach: null,
        files: [],
        notes: [],
        wakes: [],
        usage: { total: nothing, lastWeek: nothing },
      });
      expect(
        JSON.parse((await call('hire_coach', { squad, coach: 'xiaohun' })).text),
      ).toStrictEqual({ version: 1, coach: 'xiaohun' });
      expect(await coaching()).toMatchObject({ coach: 'xiaohun' });
      expect(await call('hire_coach', { squad, coach: 'xiaohun' })).toMatchObject({
        isError: true,
        text: 'COACH_ALREADY_HIRED: The squad has hired xiaohun already; fire it first.',
      });
      expect(await call('hire_coach', { squad: randomUUID(), coach: 'xiaohun' })).toMatchObject({
        isError: true,
        text: 'COACH_SQUAD_NOT_FOUND: No such squad.',
      });
      expect(JSON.parse((await call('fire_coach', { squad })).text)).toStrictEqual({
        version: 1,
        fired: 'xiaohun',
      });
      expect(await call('fire_coach', { squad })).toMatchObject({
        isError: true,
        text: 'NO_COACH_HIRED: The squad has no coach to fire.',
      });
      const hires = await sql<{ kind: string; coach_id: string; changed_by: string }>`
        select kind, coach_id, changed_by from public.squad_coach_events where squad_id = ${squad} order by id
      `.execute(db);
      expect(hires.rows).toStrictEqual([
        { kind: 'hired', coach_id: 'xiaohun', changed_by: admin.userId },
        { kind: 'fired', coach_id: 'xiaohun', changed_by: admin.userId },
      ]);

      const renamed = await call('put_coach', { ...edit, catchphrase: '先练再说' });
      expect(JSON.parse(renamed.text)).toStrictEqual({ ...xiaohun, catchphrase: '先练再说' });

      // Not an OpenAI model, a coach missing a field, or no change at all.
      for (const [name, args] of [
        ['change_coach_settings', { model: 'anthropic/claude-haiku-5-5' }],
        ['change_coach_settings', {}],
        ['put_coach', { id: 'nuannuan', name: '暖暖' }],
      ] as const) {
        expect((await call(name, args)).isError).toBe(true);
      }

      const logged = await sql<{ settings: unknown }>`
        select settings from public.coach_setting_events where changed_by = ${admin.userId}
      `.execute(db);
      expect(logged.rows.map((row) => row.settings)).toStrictEqual([
        { ...settings, coaching: true },
      ]);
      const actions = await sql<{ action: { tool: string } }>`
        select action from public.admin_actions where admin_id = ${admin.userId} order by id
      `.execute(db);
      expect(actions.rows.map(({ action }) => action.tool)).toStrictEqual([
        'change_coach_settings',
        'hire_coach',
        'fire_coach',
        'put_coach',
      ]);
    } finally {
      await call('change_coach_settings', { coaching: settings.coaching });
      await call('put_coach', edit);
      await sql`delete from public.squads where id = ${squad}`.execute(db);
    }
    expect(await read('get_coach_settings')).toStrictEqual(settings);
    expect(Coaches.parse(await read('list_coaches')).coaches).toStrictEqual(listed);
    await client.close();
  });

  it('reads and changes the 战报 words, logging each change once', async () => {
    const admin = await member({ admin: true });
    const client = await connect(clientSignedInAs(admin));
    const call = async (name: string, args: Record<string, unknown> = {}) => {
      const result = await client.callTool({ name, arguments: args });
      return { isError: result.isError === true, text: textOf(result) };
    };
    const Words = z.object({
      awards: z.record(z.string(), z.json()),
      stats: z.record(z.string(), z.json()),
    });
    const before = Words.parse(JSON.parse((await call('get_week_summary_words')).text));
    expect(before.stats.checkIns).toStrictEqual({ 'zh-Hans': '打卡', en: 'Check-ins' });
    const logged = async () =>
      (
        await sql<{ words: unknown }>`
          select words from public.week_summary_word_events
          where changed_by = ${admin.userId} order by id
        `.execute(db)
      ).rows.map(({ words }) => words);

    try {
      const checkIns = { 'zh-Hans': '打卡次数', en: 'Check-ins logged' };
      const changed = Words.parse(
        JSON.parse((await call('change_week_summary_words', { stats: { checkIns } })).text),
      );
      expect(changed).toStrictEqual({ ...before, stats: { ...before.stats, checkIns } });
      await call('change_week_summary_words', { stats: { checkIns } });
      expect(await logged()).toStrictEqual([{ version: 1, ...changed }]);

      // An award or count the API doesn't have, a winner's words without the number, or nothing.
      for (const args of [
        { stats: { laps: checkIns } },
        {
          awards: {
            crown: {
              symbol: 'crown.fill',
              title: { 'zh-Hans': '皇冠', en: 'Crown' },
              winner: {
                'zh-Hans': { one: '练了几天', other: '练了 {n} 天' },
                en: { one: '{n} day', other: '{n} days' },
              },
            },
          },
        },
        {},
      ]) {
        expect((await call('change_week_summary_words', args)).isError).toBe(true);
      }
      expect(await logged()).toHaveLength(1);
    } finally {
      await call('change_week_summary_words', { stats: { checkIns: before.stats.checkIns } });
    }
    expect(Words.parse(JSON.parse((await call('get_week_summary_words')).text))).toStrictEqual(
      before,
    );
    await client.close();
  });

  it('reads and replaces the 请假条 dice lines, logging each change once', async () => {
    const admin = await member({ admin: true });
    const client = await connect(clientSignedInAs(admin));
    const call = async (name: string, args: Record<string, unknown> = {}) => {
      const result = await client.callTool({ name, arguments: args });
      return { isError: result.isError === true, text: textOf(result) };
    };
    const Dice = z.object({
      version: z.literal(1),
      lines: z.array(z.object({ zhHans: z.string(), en: z.string(), zhHant: z.string() })),
    });
    const before = Dice.parse(JSON.parse((await call('get_disclaimer_dice')).text));
    expect(before.lines[0]).toStrictEqual({
      zhHans: '昨天的腿还没回来',
      en: "My legs haven't come back from yesterday",
      zhHant: '昨天的腿還沒回來',
    });
    const logged = async () =>
      (
        await sql<{ dice: unknown }>`
          select dice from public.disclaimer_dice_events
          where changed_by = ${admin.userId} order by id
        `.execute(db)
      ).rows.map(({ dice }) => dice);

    try {
      const lines = [
        { zhHans: '腿说休息', en: 'Legs said rest', zhHant: '腿說休息' },
        ...before.lines.slice(1),
      ];
      const changed = Dice.parse(
        JSON.parse((await call('change_disclaimer_dice', { lines })).text),
      );
      expect(changed).toStrictEqual({ version: 1, lines });
      await call('change_disclaimer_dice', { lines });
      expect(await logged()).toStrictEqual([{ version: 1, lines }]);

      // Too few lines, the same line twice, one missing a language, one too long, or nothing.
      for (const args of [
        { lines: lines.slice(0, 2) },
        { lines: [lines[0], ...lines.slice(0, 3)] },
        { lines: [{ zhHans: '腿说休息', en: 'Legs said rest' }, ...lines.slice(1)] },
        { lines: [{ ...lines[0], en: 'x'.repeat(61) }, ...lines.slice(1)] },
        {},
      ]) {
        expect((await call('change_disclaimer_dice', args)).isError).toBe(true);
      }
      expect(await logged()).toHaveLength(1);
    } finally {
      await call('change_disclaimer_dice', { lines: before.lines });
    }
    expect(Dice.parse(JSON.parse((await call('get_disclaimer_dice')).text))).toStrictEqual(before);
    await client.close();
  });

  it('reads the sports list and logs a change to it, refusing one that breaks its rules', async () => {
    const admin = await member({ admin: true });
    const client = await connect(clientSignedInAs(admin));
    const call = async (name: string, args: Record<string, unknown> = {}) => {
      const result = await client.callTool({ name, arguments: args });
      return { isError: result.isError === true, text: textOf(result) };
    };
    const before = await call('get_sports');
    const Catalog = z.object({
      version: z.literal(1),
      categories: z.array(
        z.object({ id: z.string(), sports: z.array(z.object({ id: z.string() }).loose()) }),
      ),
      picks: z.record(z.string(), z.array(z.string())),
    });
    const catalog = Catalog.parse(JSON.parse(before.text));
    const strength = catalog.categories
      .flatMap(({ id, sports }) => sports.map((sport) => ({ ...sport, category: id })))
      .find(({ id }) => id === 'strength');
    // Putting a sport back as it is changes nothing in the list, but the call is still logged.
    // Changes that stick are tested in the sports module, inside transactions rolled back, so
    // other tests keep reading the seeded list.
    const same = await call('put_sport', { ...strength });
    expect(same.isError).toBe(false);
    expect(JSON.parse(same.text)).toStrictEqual(JSON.parse(before.text));
    const refused = await call('set_sport_picks', { list: 'checkInQuick', sports: ['quidditch'] });
    expect(refused).toStrictEqual({
      isError: true,
      text: 'SPORT_NOT_OFFERED: quidditch is not a sport the pickers offer.',
    });
    const rows = await sql<{ action: unknown }>`
      select action from public.admin_actions where admin_id = ${admin.userId} order by at
    `.execute(db);
    expect(rows.rows.map(({ action }) => action)).toStrictEqual([
      { version: 1, tool: 'put_sport', arguments: { ...strength } },
    ]);
    await client.close();
  });

  it('keeps no change whose log row could not be written', async () => {
    const admin = await member({ admin: true });
    const client = await connect(clientSignedInAs(admin));
    const phrase = `${logFails}${randomUUID().slice(0, 8)}`;
    await client.callTool({
      name: 'add_memes',
      arguments: {
        memes: [
          {
            phrase,
            background: '网线被拔了。',
            meaning: '断了。',
            styles: ['funny'],
            source: '微博',
          },
        ],
      },
    });

    const failed = await client.callTool({ name: 'turn_off_meme', arguments: { phrase } });

    expect(failed.isError).toBe(true);
    const meme = await sql<{ disabled_at: Date | null }>`
      select disabled_at from public.memes where phrase = ${phrase}
    `.execute(db);
    expect(meme.rows).toStrictEqual([{ disabled_at: null }]);
    const rows = await sql<{ action: { tool: string } }>`
      select action from public.admin_actions where admin_id = ${admin.userId} order by id
    `.execute(db);
    expect(rows.rows.map(({ action }) => action.tool)).toStrictEqual(['add_memes']);
    await client.close();
  });

  it('lets no client register itself, so only clients we registered get a member’s approval', async () => {
    const response = await fetch(`${config.supabaseUrl}/auth/v1/oauth/clients/register`, {
      method: 'POST',
      headers: { apikey: publishableKey, 'content-type': 'application/json' },
      body: JSON.stringify({ ...clientMetadata, client_name: 'Someone else' }),
    });
    expect(response.ok).toBe(false);
  });

  it('refuses a member who signed in but is not on the admin list', async () => {
    // The consent page refuses them, so they approve through Supabase's API directly.
    const provider = clientSignedInAs(await member({ admin: false }), {
      approveThrough: 'auth API',
    });
    const client = new Client({ name: 'admin-mcp-test', version: '1.0.0' });
    const first = new StreamableHTTPClientTransport(mcpUrl, { authProvider: provider });
    await expect(client.connect(first)).rejects.toThrow(UnauthorizedError);
    await first.finishAuth(provider.code());
    const tokens = await provider.tokens();

    const response = await fetch(mcpUrl, {
      method: 'POST',
      headers: { authorization: `Bearer ${tokens?.access_token ?? ''}` },
    });
    expect([response.status, await response.json()]).toStrictEqual([
      403,
      {
        version: 1,
        type: 'about:blank',
        title: 'Forbidden',
        status: 403,
        detail: 'Only admins can use these tools.',
        reason: 'NOT_AN_ADMIN',
        errorStatus: 'PERMISSION_DENIED',
      },
    ]);
  });

  it('keeps an MCP sign-in, even an admin’s, out of the app’s routes', async () => {
    const provider = clientSignedInAs(await member({ admin: true }));
    await (await connect(provider)).close();
    const tokens = await provider.tokens();
    const authorization = `Bearer ${tokens?.access_token ?? ''}`;
    const refused = {
      version: 1,
      type: 'about:blank',
      title: 'Unauthorized',
      status: 401,
      detail: 'Sign in from the app to do this.',
      reason: 'APP_SIGN_IN_REQUIRED',
      errorStatus: 'UNAUTHENTICATED',
    };
    const read = await fetch(new URL('/me', mcpUrl), { headers: { authorization } });
    expect([read.status, await read.json()]).toStrictEqual([401, refused]);
    // Deleting the account checks the session with Auth too, which can't tell the client apart.
    const deleted = await fetch(new URL('/me', mcpUrl), {
      method: 'DELETE',
      headers: { authorization, 'content-type': 'application/json' },
      body: JSON.stringify({ version: 1 }),
    });
    expect([deleted.status, await deleted.json()]).toStrictEqual([401, refused]);
  });

  it('refuses our own app’s sign-in, even an admin’s, and says where to sign in', async () => {
    const { token } = await member({ admin: true });
    const response = await fetch(mcpUrl, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}` },
    });
    expect({
      status: response.status,
      challenge: response.headers.get('www-authenticate'),
      body: await response.json(),
    }).toStrictEqual({
      status: 401,
      challenge: `Bearer error="invalid_token", resource_metadata="${metadataUrl()}"`,
      body: {
        version: 1,
        type: 'about:blank',
        title: 'Unauthorized',
        status: 401,
        detail: 'Sign in from your MCP client to use the admin tools.',
        reason: 'ADMIN_SIGN_IN_REQUIRED',
        errorStatus: 'UNAUTHENTICATED',
      },
    });
  });

  it('points a client with no token at its sign-in', async () => {
    const response = await fetch(mcpUrl, { method: 'POST' });
    expect([response.status, response.headers.get('www-authenticate')]).toStrictEqual([
      401,
      `Bearer resource_metadata="${metadataUrl()}"`,
    ]);

    const metadata = await fetch(metadataUrl());
    expect(await metadata.json()).toStrictEqual({
      resource: mcpUrl.href,
      authorization_servers: [`${config.supabaseUrl}/auth/v1`],
      bearer_methods_supported: ['header'],
      resource_name: 'Wildcard admin',
    });
  });
});

const metadataUrl = () => `${mcpUrl.origin}/.well-known/oauth-protected-resource/mcp`;
