import { MemberId as ConsentMember, type AiConsent } from '@wildcard/ai-consent';
import { MemberId as SquadMember, type Squads } from '@wildcard/squads';

import type { UserId } from '../ports.js';

/**
 * Withdraws a member's AI consent. Being in a squad needs it, so they leave every squad first:
 * a failure part way leaves them with their consent, and repeating the request finishes it.
 */
export async function withdrawAiConsent(
  deps: { readonly aiConsent: AiConsent; readonly squads: Squads },
  member: UserId,
): Promise<void> {
  const inSquads = SquadMember.parse(member);
  for (const squad of await deps.squads.squadIdsOf(inSquads)) {
    await deps.squads.leave({ squad, member: inSquads });
  }
  await deps.aiConsent.withdraw(ConsentMember.parse(member));
}
