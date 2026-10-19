import { z } from 'zod';

// Plain `z.object`: the environment holds many other variables, by design.
const Environment = z.object({
  PORT: z.coerce.number().pipe(z.int().min(1).max(65535)).default(8080),
  DATABASE_URL: z.url({ protocol: /^postgres(ql)?$/ }),
  SUPABASE_URL: z.url({ protocol: /^https?$/ }),
  // A Supabase secret key (`sb_secret_…`), for Storage. Never the app's publishable key.
  SUPABASE_SECRET_KEY: z.string().startsWith('sb_secret_'),
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
});

const APNS = ['APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_PRIVATE_KEY', 'APNS_TOPIC'] as const;

export interface Config {
  readonly port: number;
  readonly databaseUrl: string;
  readonly supabaseUrl: string;
  readonly supabaseSecretKey: string;
  /** Undefined until there is an APNs key: then no pushes are sent. */
  readonly apns?: {
    readonly keyId: string;
    readonly teamId: string;
    readonly privateKey: string;
    readonly topic: string;
  };
}

/** Reads the server's settings from environment variables; throws naming each bad one. */
export function readConfig(environment: Record<string, string | undefined>): Config {
  const result = Environment.safeParse(environment);
  if (!result.success) {
    throw new Error(`Bad server environment:\n${z.prettifyError(result.error)}`);
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
    ...(APNS_KEY_ID === undefined ||
    APNS_TEAM_ID === undefined ||
    APNS_PRIVATE_KEY === undefined ||
    APNS_TOPIC === undefined
      ? {}
      : {
          apns: {
            keyId: APNS_KEY_ID,
            teamId: APNS_TEAM_ID,
            privateKey: APNS_PRIVATE_KEY,
            topic: APNS_TOPIC,
          },
        }),
  };
}
