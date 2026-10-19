import type { DraftReason, DraftStyle, MemberId } from '../../domain/draft-request.js';
import { mentionsSelfHarm } from '../../domain/draft-request.js';
import { ModelReply, outcomeOf, type DraftsOutcome } from '../../domain/drafts.js';
import { INSTRUCTIONS, promptFor } from '../../domain/prompt.js';
import { DisclaimerDraftsUsedUpError, DisclaimerWriterUnavailableError } from '../../errors.js';
import type { Clock, DraftAllowance, LanguageModel, MemesInUse } from '../../ports.js';

/** Batches a member may ask for in a day: the first and 5 换一批 (spec A4). */
export const BATCHES_PER_DAY = 6;
/** A day, for the allowance: the last 24 hours, so it needs no time zone. */
const DAY_MS = 86_400_000;
/** The most memes the prompt lists. */
const MEMES_MAX = 8;

export interface WriteDisclaimerDraftsInput {
  readonly member: MemberId;
  readonly reason: DraftReason;
  readonly style: DraftStyle;
}

/**
 * Three drafts for a member's 请假条, written by the model from their reason, or the care
 * line, or a decline. Only asked for when the member taps the button, never as they type.
 */
export async function writeDisclaimerDrafts(
  deps: {
    readonly model: LanguageModel;
    readonly memes: MemesInUse;
    readonly allowance: DraftAllowance;
    readonly clock: Clock;
  },
  input: WriteDisclaimerDraftsInput,
): Promise<DraftsOutcome> {
  if (mentionsSelfHarm(input.reason)) return { kind: 'care' };

  const now = deps.clock();
  const reservation = await deps.allowance.reserve({
    member: input.member,
    at: now,
    since: new Date(now.getTime() - DAY_MS),
    limit: BATCHES_PER_DAY,
  });
  if (reservation === undefined) throw new DisclaimerDraftsUsedUpError();

  try {
    const memes = (await deps.memes())
      .filter((meme) => meme.styles.includes(input.style))
      .slice(0, MEMES_MAX);
    const reply = await deps.model.answer({
      instructions: INSTRUCTIONS,
      prompt: promptFor({ reason: input.reason, style: input.style, memes }),
      reply: ModelReply,
    });
    const outcome = outcomeOf(reply, input.reason);
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
