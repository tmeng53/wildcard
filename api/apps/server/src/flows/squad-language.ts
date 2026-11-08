import type { ReaderLanguage } from '@wildcard/language-model';
import { MemberId, type Members } from '@wildcard/members';
import { SquadId, type Squads } from '@wildcard/squads';

// What the whole squad reads (the coach's 战术板, the weekly awards) is written once, in its
// captain's language (Tracy, 2026-11-08); what one member reads, in their own.

/**
 * The language each of `members` reads, by member (Simplified Chinese, the app's default,
 * until their app says another), and the squad's: its captain's.
 */
export async function squadLanguages(
  deps: {
    readonly members: Pick<Members, 'languages'>;
    readonly squads: Pick<Squads, 'captainOf'>;
  },
  { squad, members }: { readonly squad: string; readonly members: readonly string[] },
): Promise<{
  readonly of: (member: string) => ReaderLanguage;
  readonly squad: ReaderLanguage;
}> {
  const captain = await deps.squads.captainOf(SquadId.parse(squad));
  const everyone = captain === undefined ? members : [...new Set([...members, captain])];
  const languages = await deps.members.languages(everyone.map((member) => MemberId.parse(member)));
  const of = (member: string) => languages.get(MemberId.parse(member)) ?? 'zh-Hans';
  return { of, squad: captain === undefined ? 'zh-Hans' : of(captain) };
}
