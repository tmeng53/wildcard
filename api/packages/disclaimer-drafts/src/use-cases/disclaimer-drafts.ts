import type { DraftsOutcome } from '../domain/drafts.js';
import type { Clock, DraftAllowance, LanguageModel, MemesInUse, Random } from '../ports.js';
import {
  writeDisclaimerDrafts,
  type WriteDisclaimerDraftsInput,
} from './disclaimer-drafts/write-disclaimer-drafts.js';

/** AI drafts for 请假条. */
export interface DisclaimerDrafts {
  write(input: WriteDisclaimerDraftsInput): Promise<DraftsOutcome>;
}

export function createDisclaimerDrafts(deps: {
  readonly model: LanguageModel;
  readonly memes: MemesInUse;
  readonly allowance: DraftAllowance;
  readonly clock: Clock;
  readonly random: Random;
}): DisclaimerDrafts {
  return { write: (input) => writeDisclaimerDrafts(deps, input) };
}
