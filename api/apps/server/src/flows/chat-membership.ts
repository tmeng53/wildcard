import { MemberId as ChatMember, type ChatMembership } from '@wildcard/squad-chat';
import { MemberId as SquadsMember, SquadId as SquadsSquad, type Squads } from '@wildcard/squads';

/** Who is in which squad and since when, as the chat asks it: the squads module's to keep. */
export function chatMembership(squads: Pick<Squads, 'listMine' | 'membersOf'>): ChatMembership {
  return {
    joinedAt: async ({ squad, member }) =>
      (await squads.listMine(SquadsMember.parse(member)))
        .find(({ id }) => id === squad)
        ?.members.find((each) => each.member === member)?.joinedAt,
    membersOf: async (squad) =>
      (await squads.membersOf(SquadsSquad.parse(squad))).map((member) => ChatMember.parse(member)),
  };
}
