import type { InviteCodes } from '../domain/invite-code.js';
import {
  SceneWeek,
  sceneIn,
  type OpenScenes,
  type ScenePick,
  type Scene,
} from '../domain/scene.js';
import type { MemberId, Squad, SquadId, SquadName } from '../domain/squad.js';
import type { AiConsentCheck, PickOutcome, SquadExit, SquadStore } from '../ports.js';
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
import { setSquadLanguage } from './squads/language.js';
import { setSquadTimeZone, squadTimeZone, type SquadTimeZone } from './squads/time-zone.js';
import { setWeeklyGoal, weeklyGoal, type WeeklyGoal } from './squads/weekly-goal.js';
import { zoneAt, zoneFor } from '../domain/time-zone.js';
import type { ReaderLanguage } from '@wildcard/language-model';
import type { TimeZone } from '@wildcard/time-zones';
import type { GoalSuggestion } from '../domain/goal-suggestion.js';
import { goalFor, type DaysPerMember, type WeeklyGoalSetting } from '../domain/weekly-goal.js';

/** A squad as it stood at a moment in a week. */
export interface SquadAt {
  readonly name: SquadName;
  readonly scene: Scene;
  readonly members: readonly MemberId[];
}

/** Each squad's time zone: New York for one that never set one, so every squad has one. */
export type SquadZones = (squad: SquadId) => TimeZone;

/** Squads: creating one, joining by invite code, leaving, and who is in each. */
export interface Squads {
  /**
   * `week` is the creator's week now (its Monday, `YYYY-MM-DD`): the goal counts from it;
   * `timeZoneWeek` the squad's week now on its zone's clock, which the zone counts from.
   */
  create(
    input: Omit<CreateSquadInput, 'week' | 'timeZoneWeek'> & {
      week: string;
      timeZoneWeek?: string | undefined;
    },
  ): Promise<CreatedSquad>;
  join(input: JoinSquadInput): Promise<JoinedSquad>;
  previewInvite(input: { inviteCode: InviteCode; viewer: MemberId }): Promise<InvitePreview>;
  /** The squad as anyone holding its invite code may see it, signed in or not. */
  previewPublicInvite(inviteCode: InviteCode): Promise<PublicInvitePreview>;
  find(input: { squad: SquadId; viewer: MemberId }): Promise<Squad>;
  /** The squads a member is in now, the earliest joined first. */
  listMine(member: MemberId): Promise<Squad[]>;
  /** The squad a member was last in, when they are in none now: how they came out of it. */
  lastExit(member: MemberId): Promise<SquadExit | undefined>;
  /** The ids of the squads a member is in now: what other modules ask instead of reading tables. */
  squadIdsOf(member: MemberId): Promise<ReadonlySet<SquadId>>;
  /** The members in a squad now, in the order they joined. */
  membersOf(squad: SquadId): Promise<MemberId[]>;
  /** Everyone in any of these squads now, each once. */
  membersOfAny(squads: readonly SquadId[]): Promise<ReadonlySet<MemberId>>;
  /**
   * Which of these squads ended, when their last member left or was removed, and when: nothing
   * runs for an ended squad any more (its awards, its coach).
   */
  endedAmong(squads: readonly SquadId[]): Promise<ReadonlyMap<SquadId, Date>>;
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
   * The squad's weekly goal (人均 N 次) in the viewer's week (its Monday, `YYYY-MM-DD`) and the
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
   * The squad's weekly goal (人均 N 次) for the week starting `week` (a Monday, `YYYY-MM-DD`):
   * what other modules ask to count a squad's week against.
   */
  daysPerMember(squad: SquadId, week: string): Promise<DaysPerMember>;
  /**
   * The squad's time zone (小队时区) in its week at `moment` (on its own clock) and the next.
   */
  timeZone(input: { squad: SquadId; viewer: MemberId; moment: Date }): Promise<SquadTimeZone>;
  /**
   * Sets the squad's time zone from the week after the squad's week at `moment` (on its own
   * clock), for its captain.
   */
  setTimeZone(input: {
    squad: SquadId;
    member: MemberId;
    timeZone: string;
    moment: Date;
  }): Promise<SquadTimeZone>;
  /**
   * Each squad's time zone for the week starting `week` (a Monday, `YYYY-MM-DD`): the clock its
   * squad-wide moments keep that week, such as the 战报 freezing Sunday 8pm. New York for a squad
   * that never set one. Read once for the squads given; the lookup always has a zone.
   */
  timeZonesFor(squads: readonly SquadId[], week: string): Promise<SquadZones>;
  /** Each squad's time zone at a moment, as `timeZonesFor` for the week the squad is in then. */
  timeZonesAt(squads: readonly SquadId[], moment: Date): Promise<SquadZones>;
  /** Sets the squad's language from now on, for its captain. */
  setLanguage(input: {
    squad: SquadId;
    member: MemberId;
    language: ReaderLanguage;
  }): Promise<ReaderLanguage>;
  /**
   * Each squad's language (小队语言) as its captain picked it; a squad that never picked one is left
   * out, and reads its captain's app language.
   */
  languagesOf(squads: readonly SquadId[]): Promise<ReadonlyMap<SquadId, ReaderLanguage>>;
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
    create: (input) =>
      createSquad(deps, {
        ...input,
        week: SceneWeek.parse(input.week),
        timeZoneWeek:
          input.timeZoneWeek === undefined ? undefined : SceneWeek.parse(input.timeZoneWeek),
      }),
    join: (input) => joinSquad(deps, input),
    previewInvite: (input) => previewInvite(deps, input),
    previewPublicInvite: (inviteCode) => previewPublicInvite(deps, inviteCode),
    find: (input) => findSquad(deps, input),
    listMine: (member) => deps.store.squadsOf(member),
    lastExit: (member) => deps.store.lastExit(member),
    squadIdsOf: (member) => deps.store.squadIdsOf(member),
    membersOf: (squad) => deps.store.membersOf(squad),
    membersOfAny: (squads) => deps.store.membersOfAny(squads),
    endedAmong: (squads) => deps.store.endedAmong(squads),
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
    timeZone: (input) => squadTimeZone(deps, input),
    setTimeZone: (input) => setSquadTimeZone(deps, input),
    timeZonesFor: async (squads, week) => {
      const settings = await deps.store.timeZones(squads);
      const parsed = SceneWeek.parse(week);
      return (squad) => zoneFor(settings.get(squad) ?? [], parsed);
    },
    timeZonesAt: async (squads, moment) => {
      const settings = await deps.store.timeZones(squads);
      return (squad) => zoneAt(settings.get(squad) ?? [], moment);
    },
    setLanguage: (input) => setSquadLanguage(deps, input),
    languagesOf: (squads) => deps.store.languages(squads),
    captainOf: async (squad) => (await deps.store.find(squad))?.captain ?? undefined,
    goalSuggestions: (squad) => deps.store.goalSuggestions(squad),
    suggestGoal: (squad, suggestion) => deps.store.suggestGoal(squad, suggestion),
    scenePicks: (squad) => deps.store.scenePicks(squad),
    savePick: (input) => deps.store.pickScene(input),
  };
}
