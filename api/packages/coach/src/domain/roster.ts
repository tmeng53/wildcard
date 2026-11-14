// Who is who for the model (Tracy, 2026-11-14: people are found by user id, never by name). Every
// task and tool result writes a member as their name with their user_id after it,
// `Tracy（3f2a9c1e）`, and every tool that takes a person takes that user_id. The name is only
// what to call them; two members may share one.

/** A member as the model knows them. */
export interface Person {
  /** What to call them: their nickname, or 队员N by the order they joined without one. */
  readonly name: string;
  /**
   * Their user id as the model reads and writes it: the first 8 characters of their member id,
   * as a short commit hash stands for the whole one, or the whole id if two members share those.
   */
  readonly userId: string;
}

/** Everyone in the squad now as the model knows them, by member id, in the order they joined. */
export type Roster = ReadonlyMap<string, Person>;

const SHORT = 8;

/**
 * Each member's name and user_id for the model. A member the model may not know by name (no
 * nickname, or no AI consent) is 队员N by the order they joined.
 */
export function rosterOf(week: {
  readonly members: readonly { readonly member: string; readonly nickname?: string | undefined }[];
}): Roster {
  const shorts = week.members.map(({ member }) => member.slice(0, SHORT));
  return new Map(
    week.members.map(({ member, nickname }, index) => {
      const short = shorts[index] ?? member;
      const shared = shorts.filter((each) => each === short).length > 1;
      const name = nickname?.trim() ?? '';
      return [
        member,
        { name: name === '' ? `队员${String(index + 1)}` : name, userId: shared ? member : short },
      ];
    }),
  );
}

/** What to call a member; 队员 for someone not on the roster. */
export function nameOf(roster: Roster, member: string): string {
  return roster.get(member)?.name ?? '队员';
}

/** A member as tasks and tool results write them: `Tracy（3f2a9c1e）`. */
export function personOf(roster: Roster, member: string): string {
  const person = roster.get(member);
  return person === undefined ? '队员' : `${person.name}（${person.userId}）`;
}

/** Several members in a row: `Tracy（3f2a9c1e）、Hannah（9b1d02aa）`. */
export function peopleOf(roster: Roster, members: Iterable<string> = roster.keys()): string {
  return [...members].map((member) => personOf(roster, member)).join('、');
}

/** The member a user_id the model wrote stands for: the short one shown, or the whole id. */
export function memberOf(roster: Roster, userId: string): string | undefined {
  const given = userId.trim().toLowerCase();
  if (given === '') return undefined;
  for (const [member, person] of roster) {
    if (person.userId === given || member === given) return member;
  }
  return undefined;
}

/** A user_id of the roster that a line members read holds, which it never should. */
export function userIdIn(roster: Roster, line: string): string | undefined {
  const said = line.toLowerCase();
  for (const [member, { userId }] of roster) {
    if (said.includes(userId)) return userId;
    // Two members who share a short id are told by their whole ids; the short one is still one.
    const short = member.slice(0, SHORT);
    if (said.includes(short)) return short;
  }
  return undefined;
}

/** The names the squad's members go by, longest first so one inside another is taken whole. */
export function namesOf(roster: Roster): readonly string[] {
  return [...roster.values()].map(({ name }) => name).sort((a, b) => b.length - a.length);
}
