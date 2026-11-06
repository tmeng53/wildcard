import type { InviteCodes } from '../domain/invite-code.js';
import {
  SceneWeek,
  sceneIn,
  type OpenScenes,
  type ScenePick,
  type Scene,
} from '../domain/scene.js';
import type { MemberId, Squad, SquadId, SquadName } from '../domain/squad.js';
import type { AiConsentCheck, PickOutcome, SquadStore } from '../ports.js';
import { createSquad, type CreatedSquad, type CreateSquadInput } from './squads/create-squad.js';
import { findSquad } from './squads/find-squad.js';
import { joinSquad, type JoinedSquad, type JoinSquadInput } from './squads/join-squad.js';
import {
  previewInvite,
  previewPublicInvite,
  type InvitePreview,
  type PublicInvitePreview,
} from './squads/preview-invite.js';
import type { InviteCode } from '../domain/invite-code.js';
import { handCaptaincy, removeMember, renameSquad } from './squads/settings.js';
import { setWeeklyGoal, weeklyGoal, type WeeklyGoal } from './squads/weekly-goal.js';
import type { GoalSuggestion } from '../domain/goal-suggestion.js';
import { goalFor, type DaysPerMember, type WeeklyGoalSetting } from '../domain/weekly-goal.js';

/** A squad as it stood at a moment in a week. */
export interface SquadAt {
  readonly name: SquadName;
  readonly scene: Scene;
  readonly members: readonly MemberId[];
}

/** Squads: creating one, joining by invite code, leaving, and who is in each. */
export interface Squads {
  /** `week` is the creator's week now (its Monday, `YYYY-MM-DD`): the goal counts from it. */
  create(input: Omit<CreateSquadInput, 'week'> & { week: string }): Promise<CreatedSquad>;
  join(input: JoinSquadInput): Promise<JoinedSquad>;
  previewInvite(input: { inviteCode: InviteCode; viewer: MemberId }): Promise<InvitePreview>;
  /** The squad as anyone holding its invite code may see it, signed in or not. */
  previewPublicInvite(inviteCode: InviteCode): Promise<PublicInvitePreview>;
  find(input: { squad: SquadId; viewer: MemberId }): Promise<Squad>;
  /** The squads a member is in now, the earliest joined first. */
  listMine(member: MemberId): Promise<Squad[]>;
  /** The ids of the squads a member is in now: what other modules ask instead of reading tables. */
  squadIdsOf(member: MemberId): Promise<ReadonlySet<SquadId>>;
  /** The members in a squad now, in the order they joined. */
  membersOf(squad: SquadId): Promise<MemberId[]>;
  /** Everyone in any of these squads now, each once. */
  membersOfAny(squads: readonly SquadId[]): Promise<ReadonlySet<MemberId>>;
  /** The members in a squad at a moment, in the order they (last) joined, from its log. */
  membersAt(squad: SquadId, moment: Date): Promise<MemberId[]>;
  /**
   * A squad as it stood at a moment in a week, for its frozen 战报: its name, that week's scene
   * and the members in it then, in the order they joined; `undefined` when there is no such
   * squad. `open` is the scenes open that week (`@wildcard/scenes`).
   */
  squadAt(input: {
    squad: SquadId;
    week: SceneWeek;
    moment: Date;
    open: OpenScenes;
  }): Promise<SquadAt | undefined>;
  /**
   * Takes the member out of the squad; nothing happens if they aren't in it. When the last member
   * leaves, the squad ends: its invite stops working, and it stays. A squad is deleted only with
   * the account of its last member.
   */
  leave(input: { squad: SquadId; member: MemberId }): Promise<void>;
  /** Renames the squad, for its captain. */
  rename(input: { squad: SquadId; member: MemberId; name: SquadName }): Promise<Squad>;
  /** Hands the captaincy to another member, for the captain. */
  handCaptaincy(input: { squad: SquadId; member: MemberId; to: MemberId }): Promise<Squad>;
  /**
   * Takes `removed` out of the squad: themselves (leaving), or anyone, for the captain. Safe to
   * repeat.
   */
  removeMember(input: { squad: SquadId; member: MemberId; removed: MemberId }): Promise<void>;
  /**
   * The squad's weekly goal (人均 N 天) in the viewer's week (its Monday, `YYYY-MM-DD`) and the
   * next.
   */
  weeklyGoal(input: { squad: SquadId; viewer: MemberId; week: string }): Promise<WeeklyGoal>;
  /**
   * Sets the squad's weekly goal from the week after `week` (the captain's week now), for its
   * captain.
   */
  setWeeklyGoal(input: {
    squad: SquadId;
    member: MemberId;
    daysPerMember: DaysPerMember;
    week: string;
  }): Promise<WeeklyGoal>;
  /**
   * The squad's weekly goal settings, the earliest week first: for whatever counts the squad's
   * weeks against its goal (`goalFor`). Read by other modules instead of tables.
   */
  weeklyGoals(squad: SquadId): Promise<WeeklyGoalSetting[]>;
  /**
   * The squad's weekly goal (人均 N 天) for the week starting `week` (a Monday, `YYYY-MM-DD`):
   * what other modules ask to count a squad's week against.
   */
  daysPerMember(squad: SquadId, week: string): Promise<DaysPerMember>;
  /** The squad's captain now; `undefined` once everyone left, or for no such squad. */
  captainOf(squad: SquadId): Promise<MemberId | undefined>;
  /** The higher goals suggested to the squad's captains, the earliest week first. */
  goalSuggestions(squad: SquadId): Promise<GoalSuggestion[]>;
  /**
   * Keeps that the captain was suggested a higher goal for the squad in a week, unless one was
   * that week already (`taken`): the caller tells the captain only on `suggested`.
   */
  suggestGoal(squad: SquadId, suggestion: GoalSuggestion): Promise<'suggested' | 'taken'>;
  /** The squad's scene picks, the earliest week first: for its scene (`createSquadScenes`). */
  scenePicks(squad: SquadId): Promise<ScenePick[]>;
  /** Saves a week's scene unless it has one: the rules are `createSquadScenes`'s. */
  savePick(input: {
    squad: SquadId;
    week: SceneWeek;
    scene: Scene;
    by: MemberId;
  }): Promise<PickOutcome>;
}

export function createSquads(deps: {
  readonly store: SquadStore;
  readonly inviteCodes: InviteCodes;
  readonly aiConsent: AiConsentCheck;
}): Squads {
  return {
    create: (input) => createSquad(deps, { ...input, week: SceneWeek.parse(input.week) }),
    join: (input) => joinSquad(deps, input),
    previewInvite: (input) => previewInvite(deps, input),
    previewPublicInvite: (inviteCode) => previewPublicInvite(deps, inviteCode),
    find: (input) => findSquad(deps, input),
    listMine: (member) => deps.store.squadsOf(member),
    squadIdsOf: (member) => deps.store.squadIdsOf(member),
    membersOf: (squad) => deps.store.membersOf(squad),
    membersOfAny: (squads) => deps.store.membersOfAny(squads),
    membersAt: (squad, moment) => deps.store.membersAt(squad, moment),
    squadAt: async ({ squad, week, moment, open }) => {
      const [found, picks, members] = await Promise.all([
        deps.store.find(squad),
        deps.store.scenePicks(squad),
        deps.store.membersAt(squad, moment),
      ]);
      if (found === undefined) return undefined;
      return { name: found.name, scene: sceneIn(picks, { current: week, open }), members };
    },
    leave: ({ squad, member }) => deps.store.leave(squad, member),
    rename: (input) => renameSquad(deps, input),
    handCaptaincy: (input) => handCaptaincy(deps, input),
    removeMember: (input) => removeMember(deps, input),
    weeklyGoal: (input) => weeklyGoal(deps, { ...input, week: SceneWeek.parse(input.week) }),
    setWeeklyGoal: (input) => setWeeklyGoal(deps, { ...input, week: SceneWeek.parse(input.week) }),
    weeklyGoals: (squad) => deps.store.weeklyGoals(squad),
    daysPerMember: async (squad, week) =>
      goalFor(await deps.store.weeklyGoals(squad), SceneWeek.parse(week)),
    captainOf: async (squad) => (await deps.store.find(squad))?.captain ?? undefined,
    goalSuggestions: (squad) => deps.store.goalSuggestions(squad),
    suggestGoal: (squad, suggestion) => deps.store.suggestGoal(squad, suggestion),
    scenePicks: (squad) => deps.store.scenePicks(squad),
    savePick: (input) => deps.store.pickScene(input),
  };
}
