import type { ReaderLanguage } from '@wildcard/language-model';
import { MemberId, type Members } from '@wildcard/members';
import { createMiddleware } from 'hono/factory';

import type { Log } from './log.js';
import type { SignedIn } from './require-caller.js';

// Which of the app's languages a request's `Accept-Language` asks for. The app sends the one it
// speaks on every call (简体中文, 繁體中文 or English), which a pick in the app changes at once.

const isLanguage = (tag: string, language: string) =>
  tag === language || tag.startsWith(`${language}-`);

/** Chinese written in Traditional characters: by its script, or by the places that write it. */
const TRADITIONAL = ['zh-hant', 'zh-tw', 'zh-hk', 'zh-mo'];

/** The app's language a language tag (lowercase) names, if any. */
function readerLanguageOfTag(tag: string): ReaderLanguage | undefined {
  if (TRADITIONAL.some((traditional) => isLanguage(tag, traditional))) return 'zh-Hant';
  if (isLanguage(tag, 'zh')) return 'zh-Hans';
  if (isLanguage(tag, 'en')) return 'en';
  return undefined;
}

/**
 * The app's language in `Accept-Language` that the client weighs highest (`q`, 1 when left
 * out), the earlier one on a tie, or `undefined` when it names none. A range weighed `q=0` is
 * not acceptable.
 */
export function readerLanguageOf(acceptLanguage: string | undefined): ReaderLanguage | undefined {
  let best: { language: ReaderLanguage; q: number } | undefined;
  for (const range of (acceptLanguage ?? '').split(',')) {
    const [tag = '', ...parameters] = range.split(';').map((part) => part.trim().toLowerCase());
    const weight = parameters.find((parameter) => parameter.startsWith('q='));
    const q = weight === undefined ? 1 : Number(weight.slice(2));
    if (!(q > 0 && q <= 1)) continue;
    const language = readerLanguageOfTag(tag);
    if (language !== undefined && (best === undefined || q > best.q)) best = { language, q };
  }
  return best?.language;
}

/** The most members whose language one server instance keeps in mind before starting over. */
const REMEMBERED_MAX = 10_000;

/**
 * How long an instance trusts what it saw: another instance may have saved a switch since, so
 * a switch back is saved within this long.
 */
const REMEMBERED_MS = 5 * 60_000;

/**
 * Keeps the language each signed-in caller's app speaks, from its `Accept-Language`, so the AI
 * writes to them in it even when no request of theirs is waiting (the coach's wakes, the weekly
 * awards). Before the route runs, so a check-in's coach reply sees a language just switched to.
 * Each instance remembers what it saw for a few minutes, so a caller costs a write only now and
 * then; a failed write is logged and the request goes on.
 */
export function rememberReaderLanguage(deps: {
  readonly members: Pick<Members, 'saveLanguage'>;
  readonly log: Pick<Log, 'warn'>;
  readonly clock: () => Date;
}) {
  const seen = new Map<string, { readonly language: ReaderLanguage; readonly at: number }>();
  return createMiddleware<SignedIn>(async (c, next) => {
    const language = readerLanguageOf(c.req.header('accept-language'));
    if (language !== undefined) {
      c.set('signedIn', async ({ userId }) => {
        const now = deps.clock().getTime();
        const last = seen.get(userId);
        if (last?.language === language && now - last.at < REMEMBERED_MS) return;
        try {
          if (await deps.members.saveLanguage(MemberId.parse(userId), language)) {
            if (seen.size >= REMEMBERED_MAX) seen.clear();
            seen.set(userId, { language, at: now });
          }
        } catch (error) {
          deps.log.warn('language not saved', { error });
        }
      });
    }
    await next();
  });
}
