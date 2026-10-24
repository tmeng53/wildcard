import type { DisclaimerStyle } from '@wildcard/disclaimer-styles';

import { STYLE_NAMES, type DraftReason, type PromptMeme } from './draft-request.js';

// The user message for 请假条 drafts. The standing instructions are a setting, kept in the
// database (DraftSettings), so their wording changes without a deploy; the product spec owns it
// and its eval cases. The reply names its outcome, so a reason about self-harm gets the care line
// and any other refused reason gets the dice.

/** The user message: the reason, the style, and this call's meme, if it got one. */
export function promptFor(request: {
  readonly reason: DraftReason;
  readonly style: DisclaimerStyle;
  readonly meme: PromptMeme | undefined;
}): string {
  const lines = [`原因：${request.reason}`, `风格：${STYLE_NAMES[request.style]}`];
  if (request.meme !== undefined) {
    lines.push(
      `本周梗：${request.meme.phrase}`,
      `  意思：${request.meme.meaning}`,
      `  背景：${request.meme.background}`,
    );
  }
  return lines.join('\n');
}
