import { AppError } from '@wildcard/errors';
import { z } from 'zod';

// @wildcard/language-model: how a module asks a language model for an answer in a set JSON
// shape, whoever provides it. Each AI module (the 请假条 drafts, the weekly awards) takes one of
// these through its own wiring; the server's provider adapters implement `ProviderModel`, and its
// usage meter turns one into a `LanguageModel` that counts each call to its payer.

/**
 * Who a model call is for, so its tokens and cost are counted to someone: the member it was
 * written for or who asked, and the squad whose AI budget pays (Tracy, 2026-11-10: every call
 * goes back to a person and a squad). A call for a whole squad names no member; a member's call
 * without a squad is counted to their squad, if they have one.
 */
export interface ModelPayer {
  readonly squad?: string;
  readonly member?: string;
}

/** What one request asks of a model. */
export interface ModelRequest<Reply> {
  /** Which model answers: `provider/model` for a module, the provider's own name inside one. */
  readonly model: string;
  /** The standing instructions (a system prompt). */
  readonly instructions: string;
  /** What to answer. */
  readonly prompt: string;
  /** The shape of the answer. */
  readonly reply: z.ZodType<Reply>;
}

/**
 * A language model that answers in a set JSON shape, counting every call to whom it is for.
 * Throws `LanguageModelUnavailableError` when it can't be reached, declines to answer, or
 * answers out of shape, and `AiBudgetSpentError` when the payer's AI budget for the day is
 * spent; each module turns these into its own errors.
 */
export interface LanguageModel {
  answer<Reply>(request: ModelRequest<Reply> & { readonly payer: ModelPayer }): Promise<Reply>;
}

/** The tokens a model call used, as its provider counts them. */
export interface TokenUsage {
  readonly requests: number;
  /** Every input token, cached ones included. */
  readonly inputTokens: number;
  /** Those of the input tokens the provider had cached, at its cheaper price. */
  readonly cachedInputTokens: number;
  readonly outputTokens: number;
}

/**
 * A provider's model, as its adapter calls it: the answer and the tokens it used. Only the
 * server's usage meter calls one, so no call goes uncounted.
 */
export interface ProviderModel {
  answer<Reply>(
    request: ModelRequest<Reply>,
  ): Promise<{ readonly reply: Reply; readonly usage: TokenUsage }>;
}

/**
 * Thrown when the model can't be reached, declines to answer, or answers out of shape. `usage`
 * holds the tokens it spent anyway (a refusal, an answer cut off), which are counted too.
 */
export class LanguageModelUnavailableError extends AppError {
  override readonly name = 'LanguageModelUnavailableError';
  readonly reason = 'LANGUAGE_MODEL_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';
  readonly usage: TokenUsage | undefined;

  constructor(options?: ErrorOptions & { readonly usage?: TokenUsage }) {
    super('The language model can’t answer right now.', options);
    this.usage = options?.usage;
  }
}

/**
 * Thrown before a call when whoever pays for it spent the day's AI budget: the squad's, or every
 * squad's together. Nothing is sent; it comes back the next day.
 */
export class AiBudgetSpentError extends AppError {
  override readonly name = 'AiBudgetSpentError';
  readonly reason = 'AI_BUDGET_SPENT';
  readonly status = 'RESOURCE_EXHAUSTED';

  constructor(why: string) {
    super(`No AI budget left today: ${why}.`);
  }
}

/** The languages the app speaks, as its language picker tags them. */
export const ReaderLanguage = z.enum(['zh-Hans', 'zh-Hant', 'en']);
export type ReaderLanguage = z.infer<typeof ReaderLanguage>;

/** The line telling a model which language to write in: Traditional Chinese as Taiwan says it. */
const WRITE_IN: Readonly<Record<ReaderLanguage, string>> = {
  'zh-Hans': '用简体中文写。',
  'zh-Hant': '用繁體中文寫，照台灣的說法。',
  en: 'Write in English.',
};

/** The line telling a model which language its reader reads, for words written for them. */
export function writeIn(language: ReaderLanguage): string {
  return WRITE_IN[language];
}
