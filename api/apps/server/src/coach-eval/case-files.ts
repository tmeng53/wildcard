import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { z } from 'zod';

import { asOf, EvalCase } from './eval-case.js';

// A cases folder: `cases/<id>.json`, each a case, and `moments/<name>.json`, a squad's state
// taken once (its week, memory files, the coach's words and the day's challenges) that cases
// name as their `moment` and replay at their own `now`.

const CaseFile = z.looseObject({ moment: z.string().optional() });
const MomentFile = z.looseObject({});

/** The folder's cases, or only those named, each as the squad was at its own `now`. */
export function readCases(folder: string, only?: readonly string[]): EvalCase[] {
  return readdirSync(join(folder, 'cases'))
    .filter((name) => name.endsWith('.json'))
    .toSorted()
    .map((name) => {
      const { moment, ...own } = CaseFile.parse(readJson(join(folder, 'cases', name)));
      const base = moment === undefined ? {} : MomentFile.parse(readJson(join(folder, moment)));
      // The moment's `source` says where it came from; the case says its own.
      return asOf(EvalCase.parse({ ...base, source: undefined, ...own }));
    })
    .filter(({ id }) => only === undefined || only.includes(id));
}

function readJson(path: string): unknown {
  return JSON.parse(readFileSync(path, 'utf8'));
}
