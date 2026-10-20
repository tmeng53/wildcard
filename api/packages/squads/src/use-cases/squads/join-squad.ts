import type { InviteCode } from '../../domain/invite-code.js';
import {
  SQUAD_MEMBER_LIMIT,
  SQUADS_PER_MEMBER,
  type MemberId,
  type Squad,
} from '../../domain/squad.js';
import {
  AiConsentRequiredError,
  InviteCodeUnknownError,
  SquadFullError,
  SquadLimitReachedError,
} from '../../errors.js';
import type { AiConsentCheck, SquadStore } from '../../ports.js';

export interface JoinSquadInput {
  readonly inviteCode: InviteCode;
  readonly member: MemberId;
}

export interface JoinedSquad {
  readonly squad: Squad;
  /** False when the member was in the squad already: joining twice is a success. */
  readonly joined: boolean;
}

/** Joins the squad an invite code belongs to. The member needs a current AI consent. */
export async function joinSquad(
  { store, aiConsent }: { readonly store: SquadStore; readonly aiConsent: AiConsentCheck },
  { inviteCode, member }: JoinSquadInput,
): Promise<JoinedSquad> {
  if (!(await aiConsent(member))) throw new AiConsentRequiredError();
  const squad = await store.findByInviteCode(inviteCode);
  if (squad === undefined) throw new InviteCodeUnknownError();
  const outcome = await store.join(squad.id, member);
  if (outcome === 'squadFull') throw new SquadFullError(SQUAD_MEMBER_LIMIT);
  if (outcome === 'squadLimit') throw new SquadLimitReachedError(SQUADS_PER_MEMBER);
  const now = await store.find(squad.id);
  if (now === undefined) throw new Error(`Squad ${squad.id} vanished.`);
  return { squad: now, joined: outcome === 'joined' };
}
