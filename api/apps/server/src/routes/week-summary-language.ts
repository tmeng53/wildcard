import type { Language } from '@wildcard/check-ins';

// Which language the Sunday summary (周日战报) is written in for a request. Its words are the
// check-ins module's, kept in the database (WeekSummaryWords).

const isLanguage = (tag: string, language: string) =>
  tag === language || tag.startsWith(`${language}-`);

/**
 * The language in `Accept-Language` the summary is written in that the client weighs highest
 * (`q`, 1 when left out), the earlier one on a tie; Chinese when none is. A range weighed `q=0`
 * is not acceptable.
 */
export function languageOf(acceptLanguage: string | undefined): Language {
  let best: { language: Language; q: number } | undefined;
  for (const range of (acceptLanguage ?? '').split(',')) {
    const [tag = '', ...parameters] = range.split(';').map((part) => part.trim().toLowerCase());
    const weight = parameters.find((parameter) => parameter.startsWith('q='));
    const q = weight === undefined ? 1 : Number(weight.slice(2));
    if (!(q > 0 && q <= 1)) continue;
    const language = isLanguage(tag, 'zh') ? 'zh-Hans' : isLanguage(tag, 'en') ? 'en' : undefined;
    if (language !== undefined && (best === undefined || q > best.q)) best = { language, q };
  }
  return best?.language ?? 'zh-Hans';
}
