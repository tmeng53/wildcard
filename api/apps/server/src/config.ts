import { z } from 'zod';

// Plain `z.object`: the environment holds many other variables, by design.
const Environment = z.object({
  PORT: z.coerce.number().pipe(z.int().min(1).max(65535)).default(8080),
  DATABASE_URL: z.url({ protocol: /^postgres(ql)?$/ }),
  // A PEM file of the CA that signs the database's certificate: set, the server talks to the
  // database over TLS and checks its certificate against it (hosted Supabase signs with its own
  // root CA, `certs/supabase-root-2021.crt`). Unset, as for local Supabase, it connects in plain.
  DATABASE_CA_FILE: z.string().min(1).optional(),
  SUPABASE_URL: z.url({ protocol: /^https?$/ }),
  // A Supabase secret key (`sb_secret_…`), for Storage. Never the app's publishable key.
  SUPABASE_SECRET_KEY: z.string().startsWith('sb_secret_'),
  // Where clients reach this API, such as `https://api.example.com`. The admin MCP server names
  // itself by it, so MCP clients know which sign-in it takes. Defaults to localhost and PORT.
  PUBLIC_URL: z.url({ protocol: /^https?$/ }).optional(),
  // `on` lets admins sign in with an email and password on the admin MCP consent page, as they
  // can on local Supabase. Off in production, where admins sign in with Apple.
  ADMIN_PASSWORD_SIGN_IN: z.enum(['on', 'off']).default('off'),
  // How many of our own proxies add an address to `X-Forwarded-For` before a request reaches the
  // server: 1 for Cloud Run on its own, more behind a load balancer. Public routes rate-limit by
  // the client address found this many entries from the end.
  PROXY_HOPS: z.coerce.number().pipe(z.int().min(1).max(5)).default(1),
  // Each language model provider's key. Which model writes what is a setting in the database
  // (provider/model), so it changes without a deploy; a model whose provider has no key here
  // writes nothing: the app shows its dice, and the weekly awards stay pending.
  OPENAI_API_KEY: z.string().min(1).optional(),
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
  // Sending push notifications through APNs with token-based `.p8` keys. Apple limits a key to
  // one environment, so there is a Sandbox key (debug builds run from Xcode) and a Production
  // key (TestFlight and the App Store); a device's token picks which one signs.
  // All six, or none: without them the server sends no pushes.
  APNS_TEAM_ID: z
    .string()
    .regex(/^[A-Z0-9]{10}$/)
    .optional(),
  APNS_TOPIC: z.string().min(1).optional(),
  APNS_SANDBOX_KEY_ID: z
    .string()
    .regex(/^[A-Z0-9]{10}$/)
    .optional(),
  // The `.p8` file's contents. A secret store may hand it over with its line breaks as `\n`.
  APNS_SANDBOX_PRIVATE_KEY: z
    .string()
    .transform((key) => key.replaceAll('\\n', '\n'))
    .pipe(z.string().includes('-----BEGIN PRIVATE KEY-----'))
    .optional(),
  APNS_PRODUCTION_KEY_ID: z
    .string()
    .regex(/^[A-Z0-9]{10}$/)
    .optional(),
  APNS_PRODUCTION_PRIVATE_KEY: z
    .string()
    .transform((key) => key.replaceAll('\\n', '\n'))
    .pipe(z.string().includes('-----BEGIN PRIVATE KEY-----'))
    .optional(),
  // What the scheduler sends to start jobs such as the daily progress push. Without it no job
  // runs. Long and random, like any secret.
  JOBS_TOKEN: z.string().min(32).optional(),
  // The service account Cloud Scheduler signs its OIDC tokens as, on the hosted server. When
  // set, only its tokens (for PUBLIC_URL) start jobs, and JOBS_TOKEN isn't used.
  JOBS_SCHEDULER_ACCOUNT: z.email().optional(),
});

const APPLE_VARIABLES = ['APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_PRIVATE_KEY', 'APPLE_CLIENT_ID'];
const APNS = [
  'APNS_TEAM_ID',
  'APNS_TOPIC',
  'APNS_SANDBOX_KEY_ID',
  'APNS_SANDBOX_PRIVATE_KEY',
  'APNS_PRODUCTION_KEY_ID',
  'APNS_PRODUCTION_PRIVATE_KEY',
] as const;

export interface Config {
  readonly port: number;
  readonly databaseUrl: string;
  /** The CA file to verify the database's TLS certificate against; undefined for no TLS. */
  readonly databaseCaFile: string | undefined;
  readonly supabaseUrl: string;
  readonly supabaseSecretKey: string;
  readonly publicUrl: URL;
  /** Admins may sign in with an email and password on the consent page (local stacks only). */
  readonly adminPasswordSignIn: boolean;
  /** How many of our proxies add to `X-Forwarded-For`; see `clientAddress`. */
  readonly proxyHops: number;
  /** Each language model provider's key; undefined for a provider without one. */
  readonly languageModelKeys: Readonly<Record<'openai' | 'anthropic', string | undefined>>;
  /** Sign in with Apple's key; undefined until it is set up. */
  readonly appleSignInKey:
    | {
        readonly teamId: string;
        readonly keyId: string;
        readonly privateKey: string;
        readonly clientId: string;
      }
    | undefined;
  /** How the scheduler proves itself; undefined until one is set up, and then no job runs. */
  readonly scheduler:
    | { readonly kind: 'google'; readonly serviceAccount: string }
    | { readonly kind: 'token'; readonly token: string }
    | undefined;
  /** Undefined until there are APNs keys: then no pushes are sent. */
  readonly apns:
    | {
        readonly teamId: string;
        readonly topic: string;
        readonly keys: Readonly<
          Record<'sandbox' | 'production', { readonly keyId: string; readonly privateKey: string }>
        >;
      }
    | undefined;
}

/** Reads the server's settings from environment variables; throws naming each bad one. */
export function readConfig(environment: Record<string, string | undefined>): Config {
  const result = Environment.safeParse(environment);
  if (!result.success) {
    throw new Error(`Bad server environment:\n${z.prettifyError(result.error)}`);
  }
  // node-postgres lets the URL's own settings (sslmode, ssl, sslrootcert...) replace the CA's,
  // which could turn the check off, so a URL that comes with a CA file carries none.
  if (
    result.data.DATABASE_CA_FILE !== undefined &&
    new URL(result.data.DATABASE_URL).search !== ''
  ) {
    throw new Error(
      'Bad server environment: DATABASE_URL has a query string, whose settings would override DATABASE_CA_FILE',
    );
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
  const apnsSet = APNS.filter((name) => result.data[name] !== undefined);
  if (apnsSet.length > 0 && apnsSet.length < APNS.length) {
    const missing = APNS.filter((name) => !apnsSet.includes(name));
    throw new Error(
      `Bad server environment: set all of ${APNS.join(', ')} or none (missing ${missing.join(', ')})`,
    );
  }
  const apns = readApns(result.data);
  return {
    port: result.data.PORT,
    databaseUrl: result.data.DATABASE_URL,
    databaseCaFile: result.data.DATABASE_CA_FILE,
    supabaseUrl: result.data.SUPABASE_URL.replace(/\/+$/, ''),
    supabaseSecretKey: result.data.SUPABASE_SECRET_KEY,
    publicUrl: new URL(result.data.PUBLIC_URL ?? `http://localhost:${String(result.data.PORT)}`),
    adminPasswordSignIn: result.data.ADMIN_PASSWORD_SIGN_IN === 'on',
    proxyHops: result.data.PROXY_HOPS,
    languageModelKeys: {
      openai: result.data.OPENAI_API_KEY,
      anthropic: result.data.ANTHROPIC_API_KEY,
    },
    appleSignInKey,
    scheduler:
      result.data.JOBS_SCHEDULER_ACCOUNT !== undefined
        ? { kind: 'google', serviceAccount: result.data.JOBS_SCHEDULER_ACCOUNT }
        : result.data.JOBS_TOKEN !== undefined
          ? { kind: 'token', token: result.data.JOBS_TOKEN }
          : undefined,
    apns,
  };
}

/** The APNs settings once `readConfig` has checked that all six are set or none is. */
function readApns(data: z.infer<typeof Environment>): Config['apns'] {
  const {
    APNS_TEAM_ID,
    APNS_TOPIC,
    APNS_SANDBOX_KEY_ID,
    APNS_SANDBOX_PRIVATE_KEY,
    APNS_PRODUCTION_KEY_ID,
    APNS_PRODUCTION_PRIVATE_KEY,
  } = data;
  if (
    APNS_TEAM_ID === undefined ||
    APNS_TOPIC === undefined ||
    APNS_SANDBOX_KEY_ID === undefined ||
    APNS_SANDBOX_PRIVATE_KEY === undefined ||
    APNS_PRODUCTION_KEY_ID === undefined ||
    APNS_PRODUCTION_PRIVATE_KEY === undefined
  ) {
    return undefined;
  }
  return {
    teamId: APNS_TEAM_ID,
    topic: APNS_TOPIC,
    keys: {
      sandbox: { keyId: APNS_SANDBOX_KEY_ID, privateKey: APNS_SANDBOX_PRIVATE_KEY },
      production: { keyId: APNS_PRODUCTION_KEY_ID, privateKey: APNS_PRODUCTION_PRIVATE_KEY },
    },
  };
}
