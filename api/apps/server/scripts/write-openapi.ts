// Writes openapi.json from the routes: `pnpm openapi` in api/. src/openapi.test.ts fails when
// the committed file and the routes disagree.
import { writeFileSync } from 'node:fs';

import { createDatabase } from '../src/adapters/postgres.js';
import { createApp } from '../src/app.js';
import { createLog } from '../src/log.js';
import { openApiJson } from '../src/openapi.js';

const unused = (): never => {
  throw new Error('Writing the OpenAPI document serves no requests');
};
// Never connected: the pool opens a connection only for a query.
const db = createDatabase('postgres://localhost/unused');
const app = createApp({ db, verifyToken: unused, log: createLog(unused) });
writeFileSync(new URL('../../openapi.json', import.meta.url), openApiJson(app));
await db.destroy();
