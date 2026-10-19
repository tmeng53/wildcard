import { z } from 'zod';

// Plain `z.object`: the environment holds many other variables, by design.
const Environment = z.object({
  PORT: z.coerce.number().pipe(z.int().min(1).max(65535)).default(8080),
  DATABASE_URL: z.url({ protocol: /^postgres(ql)?$/ }),
  SUPABASE_URL: z.url({ protocol: /^https?$/ }),
  // A Supabase secret key (`sb_secret_…`), for Storage. Never the app's publishable key.
  SUPABASE_SECRET_KEY: z.string().startsWith('sb_secret_'),
  // Where clients reach this API, such as `https://api.example.com`. The admin MCP server names
  // itself by it, so MCP clients know which sign-in it takes. Defaults to localhost and PORT.
  PUBLIC_URL: z.url({ protocol: /^https?$/ }).optional(),
  // For AI 请假条 drafts. Without it the server still runs and the app shows its dice.
  ANTHROPIC_API_KEY: z.string().min(1).optional(),
  // Sign in with Apple's key, for revoking a deleted member's Apple tokens: all four, or none
  // until the key exists (deletions then skip Apple and log a warning).
  APPLE_TEAM_ID: z
    .string()
    .regex(/^[A-Z0-9]{10}$/)
    .optional(),
  APPLE_KEY_ID: z
    .string()
    .regex(/^[A-Z0-9]{10}$/)
    .optional(),
  APPLE_PRIVATE_KEY: z.string().includes('-----BEGIN PRIVATE KEY-----').optional(),
  APPLE_CLIENT_ID: z.string().min(1).optional(),
  // Sending push notifications through APNs with a token-based `.p8` key. All four, or none:
  // without them the server sends no pushes.
  APNS_KEY_ID: z
    .string()
    .regex(/^[A-Z0-9]{10}$/)
    .optional(),
  APNS_TEAM_ID: z
    .string()
    .regex(/^[A-Z0-9]{10}$/)
    .optional(),
  // The `.p8` file's contents. A secret store may hand it over with its line breaks as `\n`.
  APNS_PRIVATE_KEY: z
    .string()
    .transform((key) => key.replaceAll('\\n', '\n'))
    .pipe(z.string().includes('-----BEGIN PRIVATE KEY-----'))
    .optional(),
  APNS_TOPIC: z.string().min(1).optional(),
  // What the scheduler sends to start jobs such as the daily progress push. Without it no job
  // runs. Long and random, like any secret.
  JOBS_TOKEN: z.string().min(32).optional(),
});

const APPLE_VARIABLES = ['APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_PRIVATE_KEY', 'APPLE_CLIENT_ID'];
const APNS = ['APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_PRIVATE_KEY', 'APNS_TOPIC'] as const;

export interface Config {
  readonly port: number;
  readonly databaseUrl: string;
  readonly supabaseUrl: string;
  readonly supabaseSecretKey: string;
  readonly publicUrl: URL;
  readonly anthropicApiKey: string | undefined;
  /** Sign in with Apple's key; undefined until it is set up. */
  readonly appleSignInKey:
    | {
        readonly teamId: string;
        readonly keyId: string;
        readonly privateKey: string;
        readonly clientId: string;
      }
    | undefined;
  /** The token that starts jobs; undefined until a scheduler is set up. */
  readonly jobsToken: string | undefined;
  /** Undefined until there is an APNs key: then no pushes are sent. */
  readonly apns:
    | {
        readonly keyId: string;
        readonly teamId: string;
        readonly privateKey: string;
        readonly topic: string;
      }
    | undefined;
}

/** Reads the server's settings from environment variables; throws naming each bad one. */
export function readConfig(environment: Record<string, string | undefined>): Config {
  const result = Environment.safeParse(environment);
  if (!result.success) {
    throw new Error(`Bad server environment:\n${z.prettifyError(result.error)}`);
  }
  const { APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY, APPLE_CLIENT_ID } = result.data;
  const appleSignInKey =
    APPLE_TEAM_ID !== undefined &&
    APPLE_KEY_ID !== undefined &&
    APPLE_PRIVATE_KEY !== undefined &&
    APPLE_CLIENT_ID !== undefined
      ? {
          teamId: APPLE_TEAM_ID,
          keyId: APPLE_KEY_ID,
          // Secret managers often keep a PEM on one line, with `\n` for its line breaks.
          privateKey: APPLE_PRIVATE_KEY.replaceAll('\\n', '\n'),
          clientId: APPLE_CLIENT_ID,
        }
      : undefined;
  if (appleSignInKey === undefined && APPLE_VARIABLES.some((name) => name in environment)) {
    throw new Error(`Bad server environment: set all of ${APPLE_VARIABLES.join(', ')}, or none.`);
  }
  const { APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_TOPIC } = result.data;
  const apnsSet = APNS.filter((name) => result.data[name] !== undefined);
  if (apnsSet.length > 0 && apnsSet.length < APNS.length) {
    const missing = APNS.filter((name) => !apnsSet.includes(name));
    throw new Error(
      `Bad server environment: set all of ${APNS.join(', ')} or none (missing ${missing.join(', ')})`,
    );
  }
  return {
    port: result.data.PORT,
    databaseUrl: result.data.DATABASE_URL,
    supabaseUrl: result.data.SUPABASE_URL.replace(/\/+$/, ''),
    supabaseSecretKey: result.data.SUPABASE_SECRET_KEY,
    publicUrl: new URL(result.data.PUBLIC_URL ?? `http://localhost:${String(result.data.PORT)}`),
    anthropicApiKey: result.data.ANTHROPIC_API_KEY,
    appleSignInKey,
    jobsToken: result.data.JOBS_TOKEN,
    apns:
      APNS_KEY_ID === undefined ||
      APNS_TEAM_ID === undefined ||
      APNS_PRIVATE_KEY === undefined ||
      APNS_TOPIC === undefined
        ? undefined
        : {
            keyId: APNS_KEY_ID,
            teamId: APNS_TEAM_ID,
            privateKey: APNS_PRIVATE_KEY,
            topic: APNS_TOPIC,
          },
  };
}
