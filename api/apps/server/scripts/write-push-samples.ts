// Writes one APNs payload per push to ios/WildcardUITests/push-samples.json, which the app's UI
// tests deliver to the simulator: `pnpm push-samples` in api/ after a push changes.
// src/push-copy.test.ts fails while the copy is stale.
import { writeFileSync } from 'node:fs';

import { pushSamplesJson } from '../src/push-samples.js';

writeFileSync(
  new URL('../../../../../ios/WildcardUITests/push-samples.json', import.meta.url),
  pushSamplesJson(),
);
