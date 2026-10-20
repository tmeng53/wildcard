import {
  ModelReply,
  titlesOf,
  topCheckInOf,
  type MemberId,
  type MemberWeek,
  type SquadId,
  type StoredAwards,
  type Title,
} from '../../domain/awards.js';
import { INSTRUCTIONS, promptFor } from '../../domain/prompt.js';
import type { WeekStart } from '../../domain/schedule.js';
import { AwardsWriterUnavailableError } from '../../errors.js';
import type { AwardsStore, LanguageModel } from '../../ports.js';

/** Calls to the model per run: one more when the first answer fails the checks. */
const ATTEMPTS = 2;

export interface GiveAwardsInput {
  readonly squad: SquadId;
  readonly weekStart: WeekStart;
  /** Everyone in the squad, in the order they joined, with their check-ins before the awards. */
  readonly members: readonly MemberWeek[];
}

/**
 * A squad's awards for the week: the ones saved already, or new ones the model writes for every
 * member who checked in, saved once. A squad where nobody checked in gets none, without asking
 * the model. Throws `AwardsWriterUnavailableError` when no answer passes the checks, saving only
 * the failed try and why.
 */
export async function giveAwards(
  deps: { readonly model: LanguageModel; readonly store: AwardsStore },
  { squad, weekStart, members }: GiveAwardsInput,
): Promise<StoredAwards> {
  const saved = await deps.store.find(squad, weekStart);
  if (saved?.status === 'given') return saved.awards;

  const winners = members.filter(({ checkIns }) => checkIns.length > 0);
  let titles: Titles = new Map<MemberId, Title[]>();
  if (winners.length > 0) {
    try {
      titles = await writeTitles(deps.model, { weekStart, winners });
    } catch (error) {
      await deps.store.recordFailure({ squad, weekStart, error: reasonOf(error) });
      throw error;
    }
  }
  const awards: StoredAwards = {
    version: 1,
    members: winners.map(({ member, checkIns }) => {
      const topCheckIn = topCheckInOf(checkIns);
      return {
        member,
        titles: titles.get(member) ?? [],
        ...(topCheckIn === undefined ? {} : { topCheckIn }),
      };
    }),
  };
  if (await deps.store.save({ squad, weekStart, awards })) return awards;
  // Another run saved first: theirs stand.
  const theirs = await deps.store.find(squad, weekStart);
  if (theirs?.status !== 'given') throw new Error('Awards were saved but can’t be read back');
  return theirs.awards;
}

/** The longest reason kept for a failed try. */
const REASON_MAX = 300;

/**
 * Why a try failed, for the admin a nudge tells: the innermost cause's message (a provider's
 * "429 insufficient_quota", a timeout), which never holds members' words.
 */
export function reasonOf(error: unknown): string {
  let innermost = error;
  while (innermost instanceof Error && innermost.cause !== undefined) innermost = innermost.cause;
  const reason =
    innermost instanceof Error ? `${innermost.name}: ${innermost.message}` : String(innermost);
  return reason.slice(0, REASON_MAX);
}

type Titles = NonNullable<ReturnType<typeof titlesOf>>;

/** Titles for every winner, asking the model up to twice for an answer that passes the checks. */
async function writeTitles(
  model: LanguageModel,
  {
    weekStart,
    winners,
  }: { readonly weekStart: WeekStart; readonly winners: readonly MemberWeek[] },
): Promise<Titles> {
  const prompt = promptFor({ weekStart, members: winners });
  let cause: unknown = new Error('The awards failed the checks');
  for (let attempt = 0; attempt < ATTEMPTS; attempt += 1) {
    try {
      const reply = await model.answer({ instructions: INSTRUCTIONS, prompt, reply: ModelReply });
      const titles = titlesOf(
        reply,
        winners.map(({ member }) => member),
      );
      if (titles !== undefined) return titles;
    } catch (error) {
      cause = error;
    }
  }
  throw new AwardsWriterUnavailableError({ cause });
}
