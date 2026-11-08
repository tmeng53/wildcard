import type { ReaderLanguage } from '@wildcard/language-model';

import type { MemberId, SquadId } from '../../domain/squad.js';
import { NotSquadCaptainError } from '../../errors.js';
import type { SquadStore } from '../../ports.js';
import { findSquad } from './find-squad.js';

interface Deps {
  readonly store: SquadStore;
}

/** Sets the squad's language from now on, for its captain. Saving the one it has changes nothing. */
export async function setSquadLanguage(
  deps: Deps,
  input: {
    readonly squad: SquadId;
    readonly member: MemberId;
    readonly language: ReaderLanguage;
  },
): Promise<ReaderLanguage> {
  await findSquad(deps, { squad: input.squad, viewer: input.member });
  const outcome = await deps.store.setLanguage({
    squad: input.squad,
    actor: input.member,
    language: input.language,
  });
  if (outcome === 'notCaptain') throw new NotSquadCaptainError();
  return input.language;
}
