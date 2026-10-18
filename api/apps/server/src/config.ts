import { z } from 'zod';

// Plain `z.object`: the environment holds many other variables, by design.
const Environment = z.object({
  PORT: z.coerce.number().pipe(z.int().min(1).max(65535)).default(8080),
  DATABASE_URL: z.url({ protocol: /^postgres(ql)?$/ }),
  SUPABASE_URL: z.url({ protocol: /^https?$/ }),
  // A Supabase secret key (`sb_secret_…`), for Storage. Never the app's publishable key.
  SUPABASE_SECRET_KEY: z.string().startsWith('sb_secret_'),
});

export interface Config {
  readonly port: number;
  readonly databaseUrl: string;
  readonly supabaseUrl: string;
  readonly supabaseSecretKey: string;
}

/** Reads the server's settings from environment variables; throws naming each bad one. */
export function readConfig(environment: Record<string, string | undefined>): Config {
  const result = Environment.safeParse(environment);
  if (!result.success) {
    throw new Error(`Bad server environment:\n${z.prettifyError(result.error)}`);
  }
  return {
    port: result.data.PORT,
    databaseUrl: result.data.DATABASE_URL,
    supabaseUrl: result.data.SUPABASE_URL.replace(/\/+$/, ''),
    supabaseSecretKey: result.data.SUPABASE_SECRET_KEY,
  };
}
