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
});

const APPLE_VARIABLES = ['APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_PRIVATE_KEY', 'APPLE_CLIENT_ID'];

export interface Config {
  readonly port: number;
  readonly databaseUrl: string;
  readonly supabaseUrl: string;
  readonly supabaseSecretKey: string;
  readonly publicUrl: URL;
  /** Sign in with Apple's key; undefined until it is set up. */
  readonly appleSignInKey:
    | {
        readonly teamId: string;
        readonly keyId: string;
        readonly privateKey: string;
        readonly clientId: string;
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
  return {
    port: result.data.PORT,
    databaseUrl: result.data.DATABASE_URL,
    supabaseUrl: result.data.SUPABASE_URL.replace(/\/+$/, ''),
    supabaseSecretKey: result.data.SUPABASE_SECRET_KEY,
    publicUrl: new URL(result.data.PUBLIC_URL ?? `http://localhost:${String(result.data.PORT)}`),
    appleSignInKey,
  };
}
