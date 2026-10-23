import type { InviteCodes } from '../../domain/invite-code.js';
import {
  isMemberOf,
  SQUADS_PER_MEMBER,
  type MemberId,
  type Squad,
  type SquadId,
  type SquadName,
} from '../../domain/squad.js';
import {
  AiConsentRequiredError,
  SquadIdConflictError,
  SquadLimitReachedError,
} from '../../errors.js';
import type { AiConsentCheck, SquadStore } from '../../ports.js';

export interface CreateSquadInput {
  readonly id: SquadId;
  readonly creator: MemberId;
  readonly name: SquadName;
}

export interface CreatedSquad {
  readonly squad: Squad;
  /** False when this was a retry of a squad already created. */
  readonly created: boolean;
}

/**
 * A fresh code repeats an existing one about once in a hundred million tries at a million
 * squads, so a few attempts always find a free one.
 */
const INVITE_CODE_ATTEMPTS = 5;

/**
 * Creates a squad under the id the app made, with only a name (a venue comes later, from squad
 * settings), and the creator as its first member, who needs a current AI consent. A retry is
 * safe, consent or not: the same squad again is a success, a different name or another member's
 * squad under that id is refused.
 */
export async function createSquad(
  {
    store,
    inviteCodes,
    aiConsent,
  }: {
    readonly store: SquadStore;
    readonly inviteCodes: InviteCodes;
    readonly aiConsent: AiConsentCheck;
  },
  { id, creator, name }: CreateSquadInput,
): Promise<CreatedSquad> {
  // A retry of a squad already made is answered as before, whatever the consent is now.
  if ((await store.find(id)) !== undefined)
    return { squad: await asRetry(store, { id, creator, name }), created: false };
  if (!(await aiConsent(creator))) throw new AiConsentRequiredError();
  for (let attempt = 0; attempt < INVITE_CODE_ATTEMPTS; attempt += 1) {
    const outcome = await store.create({ id, name, creator, inviteCode: inviteCodes() });
    if (outcome.created) return { squad: await found(store, id), created: true };
    if (outcome.refused === 'idTaken')
      return { squad: await asRetry(store, { id, creator, name }), created: false };
    if (outcome.refused === 'squadLimit') throw new SquadLimitReachedError(SQUADS_PER_MEMBER);
  }
  throw new Error(`No free invite code after ${String(INVITE_CODE_ATTEMPTS)} attempts.`);
}

/** The squad saved under the id, when it is this same squad made again by its creator. */
async function asRetry(store: SquadStore, { id, creator, name }: CreateSquadInput): Promise<Squad> {
  const squad = await found(store, id);
  if (squad.createdBy !== creator || squad.name !== name || !isMemberOf(squad, creator)) {
    throw new SquadIdConflictError(id);
  }
  return squad;
}

async function found(store: SquadStore, id: SquadId): Promise<Squad> {
  const squad = await store.find(id);
  // Squads are never deleted, so one the store just created or reported is there.
  if (squad === undefined) throw new Error(`Squad ${id} vanished.`);
  return squad;
}
