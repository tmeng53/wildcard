import {
  AiBudgetSpentError,
  LanguageModelUnavailableError,
  type LanguageModel,
  type ReaderLanguage,
} from '@wildcard/language-model';
import type { DisclaimerStyle } from '@wildcard/disclaimer-styles';

import type { DraftReason, MemberId, PromptMeme } from '../../domain/draft-request.js';
import { ModelReply, outcomeOf, type DraftsOutcome } from '../../domain/drafts.js';
import { promptFor } from '../../domain/prompt.js';
import {
  AiConsentRequiredError,
  DisclaimerDraftsUsedUpError,
  DisclaimerWriterOffError,
  DisclaimerWriterUnavailableError,
} from '../../errors.js';
import type { AiConsentCheck, DraftSettingsStore, MemesInUse, Random } from '../../ports.js';

export interface WriteDisclaimerDraftsInput {
  readonly member: MemberId;
  readonly reason: DraftReason;
  readonly style: DisclaimerStyle;
  /** The language the member's app speaks, which the drafts are written in. */
  readonly language: ReaderLanguage;
}

/**
 * Three drafts for a member's 请假条, written by the model from their reason, or the care line
 * or a decline when the model says so. Only asked for when the member taps the button, never as
 * they type, and only for a member with a current AI consent, while the settings have drafts on.
 * The model, its instructions and how often a meme comes along are settings, read on every
 * request. Each call is counted to the member and their squad, and none is made once the squad's
 * AI budget for the day is spent (Tracy, 2026-11-10).
 */
export async function writeDisclaimerDrafts(
  deps: {
    readonly model: LanguageModel;
    readonly settings: DraftSettingsStore;
    readonly memes: MemesInUse;
    readonly aiConsent: AiConsentCheck;
    readonly random: Random;
  },
  input: WriteDisclaimerDraftsInput,
): Promise<DraftsOutcome> {
  if (!(await deps.aiConsent(input.member))) throw new AiConsentRequiredError();
  const settings = await deps.settings.current();
  if (!settings.writing) throw new DisclaimerWriterOffError();

  const meme = await memeFor(deps, { style: input.style, chance: settings.memeChance });
  const reply = await deps.model
    .answer({
      model: settings.model,
      instructions: settings.instructions,
      prompt: promptFor({
        reason: input.reason,
        style: input.style,
        meme,
        language: input.language,
      }),
      reply: ModelReply,
      payer: { member: input.member },
    })
    .catch((error: unknown) => {
      // The model's failure and a spent budget are the drafts' to name; any other error (drafts
      // off) stands.
      if (error instanceof AiBudgetSpentError) throw new DisclaimerDraftsUsedUpError();
      if (error instanceof LanguageModelUnavailableError) {
        throw new DisclaimerWriterUnavailableError({ cause: error });
      }
      throw error;
    });
  const outcome = outcomeOf(reply);
  if (outcome === undefined) {
    throw new DisclaimerWriterUnavailableError({
      cause: new Error('The drafts failed the checks'),
    });
  }
  return outcome;
}

/**
 * One of this week's memes that suits the style, on `chance` of requests, or none. Never the
 * whole library: one meme at a time keeps memes in moderation and the prompt short.
 */
async function memeFor(
  deps: { readonly memes: MemesInUse; readonly random: Random },
  { style, chance }: { readonly style: DisclaimerStyle; readonly chance: number },
): Promise<PromptMeme | undefined> {
  if (deps.random() >= chance) return undefined;
  const suited = (await deps.memes()).filter((meme) => meme.styles.includes(style));
  return suited[Math.floor(deps.random() * suited.length)];
}
