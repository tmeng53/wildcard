import type { ReaderLanguage } from '@wildcard/language-model';
import { MemberId, type Members } from '@wildcard/members';
import { SquadId, type Squads } from '@wildcard/squads';

// What the whole squad reads (the coach's 战术板 and name, the weekly awards) is written once, in
// the squad's language (小队语言), which its captain picks; a squad that never picked one reads its
// captain's app language (Tracy, 2026-11-08). What one member reads, in their own.

/**
 * The language each of `members` reads, by member (Simplified Chinese, the app's default, until
 * their app says another), and the squad's: the one its captain picked, else its captain's own.
 */
export async function squadLanguages(
  deps: {
    readonly members: Pick<Members, 'languages'>;
    readonly squads: Pick<Squads, 'captainOf' | 'languagesOf'>;
  },
  { squad, members }: { readonly squad: string; readonly members: readonly string[] },
): Promise<{
  readonly of: (member: string) => ReaderLanguage;
  readonly squad: ReaderLanguage;
}> {
  const id = SquadId.parse(squad);
  const [captain, picked] = await Promise.all([
    deps.squads.captainOf(id),
    deps.squads.languagesOf([id]).then((languages) => languages.get(id)),
  ]);
  const everyone = captain === undefined ? members : [...new Set([...members, captain])];
  const languages = await deps.members.languages(everyone.map((member) => MemberId.parse(member)));
  const of = (member: string) => languages.get(MemberId.parse(member)) ?? 'zh-Hans';
  return { of, squad: picked ?? (captain === undefined ? 'zh-Hans' : of(captain)) };
}
