import { serve } from '@hono/node-server';
import { createAdmins, createPostgresAdminStore } from '@wildcard/admins';
import { createCheckIns, createPostgresCheckInStore } from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createMemes, createPostgresMemeStore } from '@wildcard/memes';

import { createDatabase } from './adapters/postgres.js';
import { listAdminLog } from './admin-mcp/tools/admin-log.js';
import { memeTools } from './admin-mcp/tools/memes.js';
import { createSupabaseTokenVerifier, supabaseAuthIssuer } from './adapters/supabase-auth.js';
import { createSupabasePhotoStorage } from './adapters/supabase-storage.js';
import { createApp } from './app.js';
import { readConfig } from './config.js';
import { createLog } from './log.js';

// The composition root: picks the real adapters and serves the API.
const config = readConfig(process.env);
const log = createLog((line) => process.stdout.write(line));
const db = createDatabase(config.databaseUrl);
const photos = createSupabasePhotoStorage({
  supabaseUrl: config.supabaseUrl,
  secretKey: config.supabaseSecretKey,
});
const admins = createAdmins({ store: createPostgresAdminStore(db), clock: () => new Date() });
const memes = createMemes({ store: createPostgresMemeStore(db), clock: () => new Date() });
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  checkIns: createCheckIns({
    store: createPostgresCheckInStore(db),
    photos,
    clock: () => new Date(),
  }),
  members: createMembers({ store: createPostgresProfileStore(db) }),
  photos,
  log,
  admin: {
    admins,
    tools: [listAdminLog({ admins }), ...memeTools({ memes, clock: () => new Date() })],
    publicUrl: config.publicUrl,
    authorizationServer: supabaseAuthIssuer(config.supabaseUrl),
  },
});

const server = serve({ fetch: app.fetch, port: config.port }, (info) => {
  log.info('listening', { port: info.port });
});

// Cloud Run sends SIGTERM before stopping an instance: finish open requests, then close the pool.
process.once('SIGTERM', () => {
  log.info('shutting down');
  server.close(() => {
    void db.destroy();
  });
});
