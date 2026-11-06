import { randomUUID } from 'node:crypto';

import { createAdmins, createPostgresAdminStore } from '@wildcard/admins';
import {
  AI_CONSENT_COPY_VERSION,
  createAiConsent,
  createPostgresConsentStore,
} from '@wildcard/ai-consent';
import {
  createMembers,
  createPostgresProfileStore,
  MemberId as ProfileMember,
} from '@wildcard/members';
import { createNudges, createPostgresNudgeStore } from '@wildcard/nudges';
import {
  createOffSender,
  createPostgresDailyPushSettings,
  createPostgresDailyPushStore,
  createPostgresDeviceStore,
  createPostgresSettingsStore,
  createPush,
  type PushSender,
} from '@wildcard/push';
import { createPostgresSceneStore, createScenes } from '@wildcard/scenes';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSwitchStore, createSwitches } from '@wildcard/switches';
import { z } from 'zod';

import type { AdminTool } from '../admin-mcp/admin-tool.js';
import { readConfig } from '../config.js';
import type { Database } from '../ports.js';

// Tests only (the build leaves this folder out). Local Supabase, as `supabase status -o env`
// prints it; scripts/verify.sh passes it in.
export const config = readConfig(process.env);
const publishableKey = z.string().min(1).parse(process.env.SUPABASE_PUBLISHABLE_KEY);

const SignUp = z.object({ access_token: z.string(), user: z.object({ id: z.uuid() }) });

/**
 * Signs a new member up through local Supabase Auth and returns their real access token, and
 * the email and password they can sign in with again.
 */
export async function signUp() {
  const credentials = { email: `${randomUUID()}@example.com`, password: randomUUID() };
  const response = await fetch(`${config.supabaseUrl}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: publishableKey, 'content-type': 'application/json' },
    body: JSON.stringify(credentials),
  });
  const body = SignUp.parse(await response.json());
  return { token: body.access_token, userId: body.user.id, ...credentials };
}

/** Signs a member's session out through local Supabase Auth, as the app's sign-out does. */
export async function signOut(token: string) {
  const response = await fetch(`${config.supabaseUrl}/auth/v1/logout`, {
    method: 'POST',
    headers: { apikey: publishableKey, authorization: `Bearer ${token}` },
  });
  if (response.status !== 204) throw new Error(`logout answered ${String(response.status)}`);
}

const unused = () => Promise.reject(new Error('unused'));

/** The admin MCP server's settings on local Supabase, with these tools. */
export function adminOn(tools: (db: Database) => readonly AdminTool[] = () => []) {
  return {
    admins: (db: Database) =>
      createAdmins({ store: createPostgresAdminStore(db), clock: () => new Date() }),
    tools,
    publicUrl: new URL('http://localhost:8080'),
    authorizationServer: new URL(`${config.supabaseUrl}/auth/v1`),
    // Tests of the consent page pass Supabase's; the rest never reach it.
    consent: {
      signInWithPassword: unused,
      appleSignInUrl: () => {
        throw new Error('unused');
      },
      exchangeCode: unused,
      request: unused,
      answer: unused,
      signOut: unused,
    },
    passwordSignIn: true,
  };
}

/** Members' AI consent on local Supabase, to the current copy. */
export function aiConsentOn(db: Database) {
  return createAiConsent({
    store: createPostgresConsentStore(db),
    copyVersion: AI_CONSENT_COPY_VERSION,
    clock: () => new Date(),
  });
}

/** Nudges on local Supabase, between squadmates as the squads module keeps them. */
export function nudgesOn(db: Database) {
  const members = createMembers({ store: createPostgresProfileStore(db) });
  return createNudges({
    store: createPostgresNudgeStore(db),
    membership: createSquads({
      store: createPostgresSquadStore(db),
      inviteCodes: randomInviteCodes,
      aiConsent: () => Promise.resolve(true),
    }),
    timeZoneOf: async (member) =>
      (await members.findProfile(ProfileMember.parse(member)))?.timeZone,
    clock: () => new Date(),
  });
}

/** Push on local Supabase's database, sending nothing (no APNs key in tests). */
export function pushOn(db: Database, sender: PushSender = createOffSender()) {
  return createPush({
    store: createPostgresDeviceStore(db),
    settings: createPostgresSettingsStore(db),
    daily: createPostgresDailyPushStore(db),
    dailySettings: createPostgresDailyPushSettings(db),
    sender,
  });
}

/** The global switches on local Supabase, as seeded (winter on its schedule). */
export function switchesOn(db: Database) {
  return createSwitches({ store: createPostgresSwitchStore(db) });
}

/** The scenes on local Supabase, as seeded: the five all year and the winter 雪场 on its switch. */
export function scenesOn(db: Database) {
  const switches = createSwitches({ store: createPostgresSwitchStore(db) });
  return createScenes({ store: createPostgresSceneStore(db), switches: () => switches.states() });
}

/** Jobs as a server without a scheduler has them: no token, so none runs. */
/** No morning notes waiting: the coach job delivers none. */
export const noCoachNotes = {
  notes: { waiting: () => Promise.resolve([]), delivered: () => Promise.resolve(false) },
  noteHour: () => Promise.resolve(8),
  tell: () => Promise.resolve(),
  clock: () => new Date(),
};
export const noJobs = {
  isScheduler: undefined,
  interactions: [],
  clock: () => new Date(),
  coachNotes: noCoachNotes,
};

/**
 * Puts `member` in `squad` as well, straight in the database: a member who joined a second squad
 * before the one-squad limit, since the API no longer lets anyone in two. A post shared to more
 * than one squad, and what each squad sees of it, still have to hold for them.
 */
export async function alsoJoinedEarlier(
  db: Database,
  { squad, member }: { readonly squad: string; readonly member: string },
) {
  await db.insertInto('squad_members').values({ squad_id: squad, member_id: member }).execute();
  await db
    .insertInto('squad_membership_events')
    .values({ squad_id: squad, member_id: member, kind: 'joined', actor_id: member })
    .execute();
}
