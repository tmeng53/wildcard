import { isMemberOf, type MemberId, type Squad, type SquadId } from '../../domain/squad.js';
import { SquadNotJoinedError } from '../../errors.js';
import type { SquadStore } from '../../ports.js';

/** A squad, for one of its members. Anyone else is told only that they aren't in it. */
export async function findSquad(
  { store }: { readonly store: SquadStore },
  { squad, viewer }: { readonly squad: SquadId; readonly viewer: MemberId },
): Promise<Squad> {
  const found = await store.find(squad);
  if (found === undefined || !isMemberOf(found, viewer)) throw new SquadNotJoinedError(squad);
  return found;
}
