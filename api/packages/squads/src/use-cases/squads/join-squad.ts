import type { InviteCode } from '../../domain/invite-code.js';
import type { JoinNote, JoinRequest } from '../../domain/join-request.js';
import {
  isMemberOf,
  SQUAD_MEMBER_LIMIT,
  SQUADS_PER_MEMBER,
  type MemberId,
  type Squad,
  type SquadId,
} from '../../domain/squad.js';
import {
  AiConsentRequiredError,
  InviteCodeUnknownError,
  SquadFullError,
  SquadLimitReachedError,
} from '../../errors.js';
import type { AiConsentCheck, JoinOutcome, SquadStore } from '../../ports.js';

export interface JoinSquadInput {
  readonly inviteCode: InviteCode;
  readonly member: MemberId;
  /** A line to the captain (备注), for a squad that needs their OK; ignored otherwise. */
  readonly note?: JoinNote | undefined;
}

/**
 * What opening an invite did: the member is in the squad (`joined` false when they were already),
 * or, where the captain's OK is needed, their request waits for it (`asked` false when it already
 * did).
 */
export type JoinedSquad =
  | { readonly squad: Squad; readonly joined: boolean }
  | { readonly request: JoinRequest; readonly asked: boolean };

/**
 * Joins the squad an invite code belongs to, or asks its captain to let the member in when the
 * squad needs that (入队要队长同意). The member needs a current AI consent, except to repeat a
 * join they made already.
 */
export async function joinSquad(
  {
    store,
    aiConsent,
    joinApprovalOn,
  }: {
    readonly store: SquadStore;
    readonly aiConsent: AiConsentCheck;
    readonly joinApprovalOn?: (() => Promise<boolean>) | undefined;
  },
  { inviteCode, member, note }: JoinSquadInput,
): Promise<JoinedSquad> {
  const squad = await store.findByInviteCode(inviteCode);
  if (squad === undefined) throw new InviteCodeUnknownError();
  if (isMemberOf(squad, member)) return { squad, joined: false };
  if (!(await aiConsent(member))) throw new AiConsentRequiredError();
  if (await needsCaptainsOk({ store, joinApprovalOn }, squad.id)) {
    const outcome = await store.askToJoin({ squad: squad.id, member, note });
    if (outcome.asked === false) return refuse(store, { outcome: outcome.refused, squad });
    return { request: outcome.request, asked: outcome.asked === 'asked' };
  }
  const outcome = await store.join(squad.id, member);
  if (outcome !== 'joined') return refuse(store, { outcome, squad });
  return { squad: await found(store, squad), joined: true };
}

/** Whether opening the squad's invite asks its captain rather than joining (入队需要审核). */
export async function needsCaptainsOk(
  {
    store,
    joinApprovalOn,
  }: {
    readonly store: SquadStore;
    readonly joinApprovalOn?: (() => Promise<boolean>) | undefined;
  },
  squad: SquadId,
): Promise<boolean> {
  if (joinApprovalOn !== undefined && !(await joinApprovalOn())) return false;
  return (await store.joinApprovals([squad])).get(squad) === true;
}

async function refuse(
  store: SquadStore,
  { outcome, squad }: { readonly outcome: Exclude<JoinOutcome, 'joined'>; readonly squad: Squad },
): Promise<JoinedSquad> {
  if (outcome === 'ended') throw new InviteCodeUnknownError();
  if (outcome === 'squadFull') throw new SquadFullError(SQUAD_MEMBER_LIMIT);
  if (outcome === 'squadLimit') throw new SquadLimitReachedError(SQUADS_PER_MEMBER);
  // Let in between the read and the write: in it already.
  return { squad: await found(store, squad), joined: false };
}

async function found(store: SquadStore, squad: Squad): Promise<Squad> {
  const now = await store.find(squad.id);
  if (now === undefined) throw new Error(`Squad ${squad.id} vanished.`);
  return now;
}
