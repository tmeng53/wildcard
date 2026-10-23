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
import type {
  AiConsentCheck,
  Clock,
  DraftAllowance,
  DraftSettingsStore,
  LanguageModel,
  MemesInUse,
  Random,
} from '../../ports.js';

/** A day, for the allowance: the last 24 hours, so it needs no time zone. */
const DAY_MS = 86_400_000;

export interface WriteDisclaimerDraftsInput {
  readonly member: MemberId;
  readonly reason: DraftReason;
  readonly style: DisclaimerStyle;
}

/**
 * Three drafts for a member's 请假条, written by the model from their reason, or the care line
 * or a decline when the model says so. Only asked for when the member taps the button, never as
 * they type, and only for a member with a current AI consent, while the settings have drafts on.
 * The model, its instructions, the daily allowance and how often a meme comes along are all
 * settings, read on every request.
 */
export async function writeDisclaimerDrafts(
  deps: {
    readonly model: LanguageModel;
    readonly settings: DraftSettingsStore;
    readonly memes: MemesInUse;
    readonly allowance: DraftAllowance;
    readonly aiConsent: AiConsentCheck;
    readonly clock: Clock;
    readonly random: Random;
  },
  input: WriteDisclaimerDraftsInput,
): Promise<DraftsOutcome> {
  if (!(await deps.aiConsent(input.member))) throw new AiConsentRequiredError();
  const settings = await deps.settings.current();
  if (!settings.writing) throw new DisclaimerWriterOffError();

  const now = deps.clock();
  const reservation = await deps.allowance.reserve({
    member: input.member,
    at: now,
    since: new Date(now.getTime() - DAY_MS),
    limit: settings.batchesPerDay,
  });
  if (reservation === undefined) throw new DisclaimerDraftsUsedUpError();

  try {
    const meme = await memeFor(deps, { style: input.style, chance: settings.memeChance });
    const reply = await deps.model.answer({
      model: settings.model,
      instructions: settings.instructions,
      prompt: promptFor({ reason: input.reason, style: input.style, meme }),
      reply: ModelReply,
    });
    const outcome = outcomeOf(reply);
    if (outcome === undefined) {
      throw new DisclaimerWriterUnavailableError({
        cause: new Error('The drafts failed the checks'),
      });
    }
    return outcome;
  } catch (error) {
    // Nothing was shown, so the request doesn't count.
    await deps.allowance.release(reservation);
    throw error;
  }
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
