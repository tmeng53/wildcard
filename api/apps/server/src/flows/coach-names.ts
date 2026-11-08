import { coachIn, type Coach } from '@wildcard/coach';
import type { Members } from '@wildcard/members';
import type { Squads } from '@wildcard/squads';

import { squadLanguages } from './squad-language.js';

// A coach goes by its name in its squad's language (Tracy, 2026-11-08: 毛头 is Poki in English),
// wherever the app shows it: its card, 动态, 通知 and pushes. Without a squad, the Chinese name.

/** Names for the coaches asked about, each as its squad calls it. */
export type CoachNames = (
  asked: readonly { readonly coach: string; readonly squad: string | undefined }[],
) => Promise<(coach: string, squad: string | undefined) => string | undefined>;

export function coachNamesIn(deps: {
  readonly coaches: { list(): Promise<readonly Coach[]> };
  readonly members: Pick<Members, 'languages'>;
  readonly squads: Pick<Squads, 'captainOf'>;
}): CoachNames {
  return async (asked) => {
    const coaches = new Map<string, Coach>(
      (await deps.coaches.list()).map((coach) => [coach.id, coach]),
    );
    const squads = [...new Set(asked.flatMap(({ squad }) => (squad === undefined ? [] : [squad])))];
    const languages = new Map(
      await Promise.all(
        squads.map(
          async (squad) =>
            [squad, (await squadLanguages(deps, { squad, members: [] })).squad] as const,
        ),
      ),
    );
    return (coach, squad) => {
      const found = coaches.get(coach);
      if (found === undefined) return undefined;
      const language = squad === undefined ? undefined : languages.get(squad);
      return coachIn(found, language ?? 'zh-Hans').name;
    };
  };
}
