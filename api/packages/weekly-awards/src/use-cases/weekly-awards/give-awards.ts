import type { LanguageModel, ReaderLanguage } from '@wildcard/language-model';
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
import {
  awardsLanguageOf,
  promptFor,
  type AwardsLanguage,
  type PromptMeme,
} from '../../domain/prompt.js';
import type { WeekStart } from '../../domain/schedule.js';
import { offeredMoves, type AwardSettings } from '../../domain/settings.js';
import { AwardsWriterUnavailableError } from '../../errors.js';
import type {
  AiConsented,
  AwardSettingsStore,
  AwardsStore,
  MemesInUse,
  SportGlyphs,
} from '../../ports.js';

/** Calls to the model per run: one more when the first fails (an error, or an answer off its schema). */
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
   * The squad's days trained against its weekly goal, for the words on its last
   * page; none when nobody trained.
   */
  readonly ending?: { readonly done: number; readonly plan: number } | undefined;
  /** The squad's language, its captain's; Simplified Chinese when left out. */
  readonly language?: ReaderLanguage | undefined;
}

/**
 * A squad's awards for the week: the ones saved already, or new ones the model writes for the
 * members who checked in and agreed to AI use (any it gives a title), with the words for the 战报's last page when the
 * squad trained, saved once, read with the comments on their posts
 * from members who agreed too. A squad where none of them did gets none, without asking the
 * model. Throws `AwardsWriterUnavailableError` when the model fails every try (an error, or an
 * answer off its schema), saving only the failed try and why; the next run tries again.
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
  { squad, weekStart, members, ending, language }: GiveAwardsInput,
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
        squad,
        settings,
        badges: withSportGlyphs(settings.badges, await deps.sportGlyphs()),
        memes: await deps.memes(),
        weekStart,
        winners,
        ending,
        language: language === undefined ? undefined : awardsLanguageOf(language),
      }));
    } catch (error) {
      await deps.store.recordFailure({ squad, weekStart, error: reasonOf(error) });
      throw error;
    }
  }
  const awards: Awards = {
    // Only members the model gave a title: it may leave anyone out.
    members: winners.flatMap(({ member }) => {
      const theirs = titles.get(member);
      return theirs === undefined ? [] : [{ member, titles: theirs }];
    }),
    ...(words === undefined ? {} : { ending: words }),
  };
  if (await deps.store.save({ squad, weekStart, awards })) return awards;
  // Another run saved first: theirs stand.
  const theirs = await deps.store.find(squad, weekStart);
  if (theirs?.status !== 'given') throw new Error('Awards were saved but can’t be read back');
  return theirs.awards;
}

/** An error's string property, when it has one. */
const fieldOf = (error: object, key: string): unknown =>
  key in error ? Reflect.get(error, key) : undefined;

/**
 * Why a try failed, for the admins a nudge tells: the innermost cause's name, with the HTTP
 * status and the provider's error code when there are any (`RateLimitError 429
 * insufficient_quota`, `APIConnectionTimeoutError`, `SyntaxError`). Never an
 * error's message, which can quote the model's answer and so members' words.
 */
export function reasonOf(error: unknown): string {
  let innermost = error;
  while (innermost instanceof Error && innermost.cause !== undefined) innermost = innermost.cause;
  if (!(innermost instanceof Error)) return 'Unknown';
  const status = fieldOf(innermost, 'status');
  const code = fieldOf(innermost, 'code');
  return [
    innermost.name,
    ...(typeof status === 'number' ? [String(status)] : []),
    ...(typeof code === 'string' && /^[a-z_]{1,40}$/u.test(code) ? [code] : []),
  ].join(' ');
}

type Titles = ReturnType<typeof titlesOf>;

/**
 * Titles for the winners the model gives any, and the words for the 战报's last page when the squad trained (the
 * model writes them either way; they are dropped without an ending), asking the model the
 * settings name up to twice for an answer that passes the checks.
 */
async function writeTitles(
  model: LanguageModel,
  {
    squad,
    settings,
    badges,
    memes,
    weekStart,
    winners,
    ending,
    language,
  }: {
    /** The squad the awards are for, whose AI budget the calls are counted to. */
    readonly squad: string;
    readonly settings: AwardSettings;
    readonly language: AwardsLanguage | undefined;
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
    language,
  });
  const reply = modelReplyFor(badges, {
    moves: offeredMoves(settings.moves),
    members: winners.length,
  });
  let cause: unknown;
  for (let attempt = 0; attempt < ATTEMPTS; attempt += 1) {
    try {
      const answer = await model.answer({
        model: settings.model,
        instructions: settings.instructions,
        prompt,
        reply,
        payer: { squad },
      });
      return {
        titles: titlesOf(
          answer,
          winners.map(({ member }) => member),
        ),
        // Without an ending the words go unused; blank ones leave the page its own words.
        words: ending === undefined ? undefined : endingWordsOf(answer),
      };
    } catch (error) {
      cause = error;
    }
  }
  throw new AwardsWriterUnavailableError({ cause });
}
