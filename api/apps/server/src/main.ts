import { serve } from '@hono/node-server';
import { createCheckIns, createPostgresCheckInStore } from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';

import { createDatabase } from './adapters/postgres.js';
import { createSupabaseTokenVerifier } from './adapters/supabase-auth.js';
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
const members = createMembers({ store: createPostgresProfileStore(db) });
const app = createApp({
  db,
  verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
  checkIns: createCheckIns({
    store: createPostgresCheckInStore(db),
    photos,
    zones: members,
    clock: () => new Date(),
  }),
  members,
  photos,
  log,
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
