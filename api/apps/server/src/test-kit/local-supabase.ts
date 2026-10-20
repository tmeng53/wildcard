import { randomUUID } from 'node:crypto';

import { createAdmins, createPostgresAdminStore } from '@wildcard/admins';
import {
  AI_CONSENT_COPY_VERSION,
  createAiConsent,
  createPostgresConsentStore,
} from '@wildcard/ai-consent';
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
