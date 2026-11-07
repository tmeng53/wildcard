import {
  endingWordsOf,
  modelReplyFor,
  type Awards,
  type EndingWords,
  titlesOf,
  type MemberId,
  type MemberWeek,
  type SquadId,
  type Title,
} from '../../domain/awards.js';
import { withSportGlyphs, type BadgeCatalog } from '../../domain/badges.js';
import { promptFor, type PromptMeme } from '../../domain/prompt.js';
import type { WeekStart } from '../../domain/schedule.js';
import { offeredMoves, type AwardSettings } from '../../domain/settings.js';
import { AwardsWriterUnavailableError } from '../../errors.js';
import type {
  AiConsented,
  AwardSettingsStore,
  AwardsStore,
  LanguageModel,
  MemesInUse,
  SportGlyphs,
} from '../../ports.js';

/** Calls to the model per run: one more when the first answer fails the checks. */
const ATTEMPTS = 2;

export interface GiveAwardsInput {
  readonly squad: SquadId;
  readonly weekStart: WeekStart;
  /**
   * Everyone in the squad at the awards, in the order they joined, with their check-ins before
   * them.
   */
  readonly members: readonly MemberWeek[];
  /**
   * The squad's days trained against its plans, as its 战报 froze them, for the words on its last
   * page; none when nobody trained.
   */
  readonly ending?: { readonly done: number; readonly plan: number } | undefined;
}

/**
 * A squad's awards for the week: the ones saved already, or new ones the model writes for every
 * member who checked in and agreed to AI use, with the words for the 战报's last page when the
 * squad trained, saved once, read with the comments on their posts
 * from members who agreed too. A squad where none of them did gets none, without asking the
 * model. Throws `AwardsWriterUnavailableError` when no answer passes the checks, saving only
 * the failed try and why.
 */
export async function giveAwards(
  deps: {
    readonly model: LanguageModel;
    readonly settings: AwardSettingsStore;
    readonly store: AwardsStore;
    readonly aiConsented: AiConsented;
    readonly memes: MemesInUse;
    readonly sportGlyphs: SportGlyphs;
  },
  { squad, weekStart, members, ending }: GiveAwardsInput,
): Promise<Awards> {
  const saved = await deps.store.find(squad, weekStart);
  if (saved?.status === 'given') return saved.awards;

  const checkedIn = members.filter(({ checkIns }) => checkIns.length > 0);
  // Whose words may go to the model: those who checked in, and whoever commented on their posts.
  const writers = new Set(checkedIn.map(({ member }) => member));
  for (const { checkIns } of checkedIn) {
    for (const { comments = [] } of checkIns)
      for (const { member } of comments) writers.add(member);
  }
  const agreed = new Set(writers.size === 0 ? [] : await deps.aiConsented([...writers]));
  const winners = checkedIn
    .filter(({ member }) => agreed.has(member))
    .map((week) => ({
      ...week,
      checkIns: week.checkIns.map((each) =>
        each.comments === undefined
          ? each
          : { ...each, comments: each.comments.filter(({ member }) => agreed.has(member)) },
      ),
    }));
  let titles: Titles = new Map<MemberId, Title[]>();
  let words: EndingWords | undefined;
  if (winners.length > 0) {
    try {
      const settings = await deps.settings.current();
      ({ titles, words } = await writeTitles(deps.model, {
        settings,
        badges: withSportGlyphs(settings.badges, await deps.sportGlyphs()),
        memes: await deps.memes(),
        weekStart,
        winners,
        ending,
      }));
    } catch (error) {
      await deps.store.recordFailure({ squad, weekStart, error: reasonOf(error) });
      throw error;
    }
  }
  const awards: Awards = {
    members: winners.map(({ member }) => ({ member, titles: titles.get(member) ?? [] })),
    ...(words === undefined ? {} : { ending: words }),
  };
  if (await deps.store.save({ squad, weekStart, awards })) return awards;
  // Another run saved first: theirs stand.
  const theirs = await deps.store.find(squad, weekStart);
  if (theirs?.status !== 'given') throw new Error('Awards were saved but can’t be read back');
  return theirs.awards;
}

/**
 * The cause kept when every reply named the wrong members (one missing, repeated or unknown) or
 * left a title or line blank, or the 战报's last page (when it has one) without its words.
 */
const FAILED_CHECKS = 'FailedChecks';

/** An error's string property, when it has one. */
const fieldOf = (error: object, key: string): unknown =>
  key in error ? Reflect.get(error, key) : undefined;

/**
 * Why a try failed, for the admins a nudge tells: the innermost cause's name, with the HTTP
 * status and the provider's error code when there are any (`RateLimitError 429
 * insufficient_quota`, `APIConnectionTimeoutError`, `SyntaxError`, `FailedChecks`). Never an
 * error's message, which can quote the model's answer and so members' words.
 */
export function reasonOf(error: unknown): string {
  let innermost = error;
  while (innermost instanceof Error && innermost.cause !== undefined) innermost = innermost.cause;
  if (innermost === FAILED_CHECKS) return FAILED_CHECKS;
  if (!(innermost instanceof Error)) return 'Unknown';
  const status = fieldOf(innermost, 'status');
  const code = fieldOf(innermost, 'code');
  return [
    innermost.name,
    ...(typeof status === 'number' ? [String(status)] : []),
    ...(typeof code === 'string' && /^[a-z_]{1,40}$/u.test(code) ? [code] : []),
  ].join(' ');
}

type Titles = NonNullable<ReturnType<typeof titlesOf>>;

/**
 * Titles for every winner, and the words for the 战报's last page when the squad trained (the
 * model writes them either way; they are dropped without an ending), asking the model the
 * settings name up to twice for an answer that passes the checks.
 */
async function writeTitles(
  model: LanguageModel,
  {
    settings,
    badges,
    memes,
    weekStart,
    winners,
    ending,
  }: {
    readonly settings: AwardSettings;
    /** The settings' badge catalog with the sports' icons among its glyphs. */
    readonly badges: BadgeCatalog;
    readonly memes: readonly PromptMeme[];
    readonly weekStart: WeekStart;
    readonly winners: readonly MemberWeek[];
    readonly ending: GiveAwardsInput['ending'];
  },
): Promise<{ titles: Titles; words: EndingWords | undefined }> {
  const prompt = promptFor({
    weekStart,
    ending,
    members: winners,
    moves: settings.moves,
    badges,
    memes,
  });
  const reply = modelReplyFor(badges, offeredMoves(settings.moves));
  let cause: unknown;
  for (let attempt = 0; attempt < ATTEMPTS; attempt += 1) {
    try {
      const answer = await model.answer({
        model: settings.model,
        instructions: settings.instructions,
        prompt,
        reply,
      });
      const titles = titlesOf(
        answer,
        winners.map(({ member }) => member),
      );
      // Without an ending the words go unused, so blank ones fail nothing.
      const words = ending === undefined ? undefined : endingWordsOf(answer);
      if (titles !== undefined && (ending === undefined || words !== undefined)) {
        return { titles, words };
      }
      cause = FAILED_CHECKS;
    } catch (error) {
      cause = error;
    }
  }
  throw new AwardsWriterUnavailableError({ cause });
}
