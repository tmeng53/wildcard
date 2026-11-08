import { AppError } from '@wildcard/errors';
import { z } from 'zod';

// @wildcard/language-model: how a module asks a language model for an answer in a set JSON
// shape, whoever provides it. Each AI module (the 请假条 drafts, the weekly awards) takes one of
// these through its own wiring; the server's provider adapters implement it.

/**
 * A language model that answers in a set JSON shape. Throws `LanguageModelUnavailableError`
 * when it can't be reached, declines to answer, or answers out of shape; each module turns that
 * into its own error.
 */
export interface LanguageModel {
  answer<Reply>(request: {
    /** Which model answers: `provider/model` for a module, the provider's own name inside one. */
    readonly model: string;
    /** The standing instructions (a system prompt). */
    readonly instructions: string;
    /** What to answer. */
    readonly prompt: string;
    /** The shape of the answer. */
    readonly reply: z.ZodType<Reply>;
  }): Promise<Reply>;
}

/** Thrown when the model can't be reached, declines to answer, or answers out of shape. */
export class LanguageModelUnavailableError extends AppError {
  override readonly name = 'LanguageModelUnavailableError';
  readonly reason = 'LANGUAGE_MODEL_UNAVAILABLE';
  readonly status = 'UNAVAILABLE';

  constructor(options?: ErrorOptions) {
    super('The language model can’t answer right now.', options);
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
