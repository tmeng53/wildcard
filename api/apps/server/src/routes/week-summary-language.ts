import type { Language } from '@wildcard/check-ins';

import { readerLanguageOf } from '../reader-language.js';

// Which language the Sunday summary (周日战报) is written in for a request. Its words are the
// check-ins module's, kept in the database (WeekSummaryWords), in Simplified Chinese, English and
// Traditional Chinese.

/** The summary's language for the app's language in `Accept-Language`; Chinese when none is. */
export function languageOf(acceptLanguage: string | undefined): Language {
  return readerLanguageOf(acceptLanguage) ?? 'zh-Hans';
}
