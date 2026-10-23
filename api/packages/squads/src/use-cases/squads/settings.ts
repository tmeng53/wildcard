import type { MemberId, Squad, SquadId, SquadName } from '../../domain/squad.js';
import { NotSquadCaptainError, SquadMemberUnknownError } from '../../errors.js';
import type { CaptainOutcome, SquadStore } from '../../ports.js';
import { findSquad } from './find-squad.js';

interface Deps {
  readonly store: SquadStore;
}

/** Renames the squad, for its captain. Saving the same name again changes nothing. */
export async function renameSquad(
  deps: Deps,
  input: { readonly squad: SquadId; readonly member: MemberId; readonly name: SquadName },
): Promise<Squad> {
  await findSquad(deps, { squad: input.squad, viewer: input.member });
  settled(
    await deps.store.rename({ squad: input.squad, actor: input.member, name: input.name }),
    input.member,
  );
  return findSquad(deps, { squad: input.squad, viewer: input.member });
}

/** Hands the captaincy to another member, for the captain. */
export async function handCaptaincy(
  deps: Deps,
  input: { readonly squad: SquadId; readonly member: MemberId; readonly to: MemberId },
): Promise<Squad> {
  await findSquad(deps, { squad: input.squad, viewer: input.member });
  settled(
    await deps.store.handCaptaincy({ squad: input.squad, actor: input.member, to: input.to }),
    input.to,
  );
  return findSquad(deps, { squad: input.squad, viewer: input.member });
}

/**
 * Takes a member out of the squad. Anyone may take themselves out (leaving); only the captain
 * may take out someone else. Safe to repeat: someone not in the squad changes nothing.
 */
export async function removeMember(
  deps: Deps,
  input: { readonly squad: SquadId; readonly member: MemberId; readonly removed: MemberId },
): Promise<void> {
  if (input.removed === input.member) {
    await deps.store.leave(input.squad, input.member);
    return;
  }
  await findSquad(deps, { squad: input.squad, viewer: input.member });
  settled(
    await deps.store.remove({ squad: input.squad, actor: input.member, member: input.removed }),
    input.removed,
  );
}

function settled(outcome: CaptainOutcome, member: MemberId) {
  if (outcome === 'notCaptain') throw new NotSquadCaptainError();
  if (outcome === 'notMember') throw new SquadMemberUnknownError(member);
}
