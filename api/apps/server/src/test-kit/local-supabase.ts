import { randomUUID } from 'node:crypto';

import { z } from 'zod';

import { readConfig } from '../config.js';

// Tests only (the build leaves this folder out). Local Supabase, as `supabase status -o env`
// prints it; scripts/verify.sh passes it in.
export const config = readConfig(process.env);
const publishableKey = z.string().min(1).parse(process.env.SUPABASE_PUBLISHABLE_KEY);

const SignUp = z.object({ access_token: z.string(), user: z.object({ id: z.uuid() }) });

/** Signs a new member up through local Supabase Auth and returns their real access token. */
export async function signUp() {
  const response = await fetch(`${config.supabaseUrl}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: publishableKey, 'content-type': 'application/json' },
    body: JSON.stringify({ email: `${randomUUID()}@example.com`, password: randomUUID() }),
  });
  const body = SignUp.parse(await response.json());
  return { token: body.access_token, userId: body.user.id };
}

/** Signs a member's session out through local Supabase Auth, as the app's sign-out does. */
export async function signOut(token: string) {
  const response = await fetch(`${config.supabaseUrl}/auth/v1/logout`, {
    method: 'POST',
    headers: { apikey: publishableKey, authorization: `Bearer ${token}` },
  });
  if (response.status !== 204) throw new Error(`logout answered ${String(response.status)}`);
}
