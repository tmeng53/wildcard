import type { JoinRequest, JoinRequestId } from '../../domain/join-request.js';
import {
  SQUAD_MEMBER_LIMIT,
  SQUADS_PER_MEMBER,
  type MemberId,
  type SquadId,
} from '../../domain/squad.js';
import {
  JoinRequestAnsweredError,
  JoinRequestUnknownError,
  NotSquadCaptainError,
  SquadFullError,
  SquadLimitReachedError,
} from '../../errors.js';
import type { SquadStore } from '../../ports.js';
import { findSquad } from './find-squad.js';

interface Deps {
  readonly store: SquadStore;
}

/** Whether joining the squad needs its captain's OK, for any member of it. */
export async function joinApproval(
  deps: Deps,
  input: { readonly squad: SquadId; readonly viewer: MemberId },
): Promise<boolean> {
  await findSquad(deps, input);
  return (await deps.store.joinApprovals([input.squad])).get(input.squad) === true;
}

/** Turns the captain's OK on or off, for the captain. */
export async function setJoinApproval(
  deps: Deps,
  input: { readonly squad: SquadId; readonly member: MemberId; readonly required: boolean },
): Promise<boolean> {
  await findSquad(deps, { squad: input.squad, viewer: input.member });
  const outcome = await deps.store.setJoinApproval({
    squad: input.squad,
    actor: input.member,
    required: input.required,
  });
  if (outcome === 'notCaptain') throw new NotSquadCaptainError();
  return input.required;
}

/** The requests waiting for the captain's OK, the earliest first, for the captain. */
export async function waitingJoinRequests(
  deps: Deps,
  input: { readonly squad: SquadId; readonly viewer: MemberId },
): Promise<JoinRequest[]> {
  const squad = await findSquad(deps, input);
  if (squad.captain !== input.viewer) throw new NotSquadCaptainError();
  return deps.store.waitingJoinRequests(input.squad);
}

/**
 * Lets a waiting member in or turns them away, for the captain. Answering again the way it was
 * answered is a success, so a retry is safe; `changed` is false then.
 */
export async function answerJoinRequest(
  deps: Deps,
  input: {
    readonly squad: SquadId;
    readonly request: JoinRequestId;
    readonly member: MemberId;
    readonly approve: boolean;
  },
): Promise<{ readonly request: JoinRequest; readonly changed: boolean }> {
  await findSquad(deps, { squad: input.squad, viewer: input.member });
  const outcome = await deps.store.answerJoinRequest({
    squad: input.squad,
    request: input.request,
    actor: input.member,
    approve: input.approve,
  });
  if (outcome === 'notCaptain') throw new NotSquadCaptainError();
  if (outcome === 'unknown') throw new JoinRequestUnknownError(input.request);
  if (outcome === 'squadFull') throw new SquadFullError(SQUAD_MEMBER_LIMIT);
  if (outcome === 'squadLimit') throw new SquadLimitReachedError(SQUADS_PER_MEMBER);
  const request = await deps.store.joinRequest(input.request);
  if (request === undefined) throw new JoinRequestUnknownError(input.request);
  const settled = request.answer?.kind === (input.approve ? 'approved' : 'declined');
  if (outcome === 'answered' && !settled) throw new JoinRequestAnsweredError(input.request);
  return { request, changed: outcome !== 'answered' };
}
