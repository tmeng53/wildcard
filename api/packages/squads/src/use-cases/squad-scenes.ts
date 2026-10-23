import {
  lastTrained,
  sceneIn,
  weekBefore,
  type Scene,
  type ScenePick,
  type SceneWeek,
} from '../domain/scene.js';
import type { MemberId, SquadId } from '../domain/squad.js';
import { NotScenePickerError, ScenePickedError, SceneWeekClosedError } from '../errors.js';
import type { CrownHolders, SceneWeekAt } from '../ports.js';
import type { Squads } from './squads.js';

/**
 * What the scene needs from outside the module: the squads, last week's crown (the check-ins'
 * week summary) and the awards' clock.
 */
export interface SceneDeps {
  readonly squads: Pick<Squads, 'find' | 'scenePicks' | 'savePick'>;
  readonly crownHolders: CrownHolders;
  readonly sceneWeekAt: SceneWeekAt;
  readonly clock: () => Date;
}

/** A squad's scene this week, who picks it, and when the squad last trained on each scene. */
export interface SquadScene {
  /** The Monday of the week open for picking now. */
  readonly week: SceneWeek;
  readonly scene: Scene;
  /** Who picks this week's scene: last week's crown winners, or the captain when nobody won. */
  readonly pickers: { readonly by: 'crown' | 'captain'; readonly members: readonly MemberId[] };
  /** This week's pick, once made. */
  readonly picked: ScenePick | undefined;
  /** True when the viewer may pick now: one of the pickers, and nothing picked yet. */
  readonly canPick: boolean;
  /** Every scene and how many weeks ago the squad last trained on it (0: this week; null: never). */
  readonly lastTrained: ReadonlyMap<Scene, number | null>;
}

/** Each squad's scene for the week, picked once a week (小队设置 and the 战报's last page). */
export interface SquadScenes {
  /** The squad's scene, for one of its members. */
  scene(input: { readonly squad: SquadId; readonly viewer: MemberId }): Promise<SquadScene>;
  /**
   * Picks the scene for the week open now, once: a retry of the same pick by the same member
   * answers as before, with `picked` false.
   */
  pick(input: {
    readonly squad: SquadId;
    readonly member: MemberId;
    readonly week: SceneWeek;
    readonly scene: Scene;
  }): Promise<{ readonly scene: SquadScene; readonly picked: boolean }>;
}

export function createSquadScenes(deps: SceneDeps): SquadScenes {
  return {
    scene: (input) => squadScene(deps, input),
    pick: (input) => pickScene(deps, input),
  };
}

async function squadScene(
  deps: SceneDeps,
  input: { readonly squad: SquadId; readonly viewer: MemberId },
): Promise<SquadScene> {
  const squad = await deps.squads.find({ squad: input.squad, viewer: input.viewer });
  const week = deps.sceneWeekAt(deps.clock());
  const [picks, crown] = await Promise.all([
    deps.squads.scenePicks(squad.id),
    deps.crownHolders({ squad: squad.id, week: weekBefore(week), viewer: input.viewer }),
  ]);
  const inSquad = crown.filter((member) => squad.members.some((each) => each.member === member));
  const pickers =
    inSquad.length > 0
      ? { by: 'crown' as const, members: inSquad }
      : { by: 'captain' as const, members: squad.captain === null ? [] : [squad.captain] };
  const picked = picks.find((pick) => pick.week === week);
  return {
    week,
    scene: sceneIn(picks, week),
    pickers,
    picked,
    canPick: picked === undefined && pickers.members.includes(input.viewer),
    lastTrained: lastTrained(picks, {
      firstWeek: deps.sceneWeekAt(squad.createdAt),
      current: week,
    }),
  };
}

async function pickScene(
  deps: SceneDeps,
  input: {
    readonly squad: SquadId;
    readonly member: MemberId;
    readonly week: SceneWeek;
    readonly scene: Scene;
  },
): Promise<{ readonly scene: SquadScene; readonly picked: boolean }> {
  const now = await squadScene(deps, { squad: input.squad, viewer: input.member });
  if (input.week !== now.week) throw new SceneWeekClosedError(input.week);
  if (now.picked !== undefined) {
    if (now.picked.by === input.member && now.picked.scene === input.scene) {
      return { scene: now, picked: false };
    }
    throw new ScenePickedError(input.week);
  }
  if (!now.canPick) throw new NotScenePickerError();
  const outcome = await deps.squads.savePick({
    squad: input.squad,
    week: input.week,
    scene: input.scene,
    by: input.member,
  });
  if (outcome === 'taken') throw new ScenePickedError(input.week);
  return {
    scene: await squadScene(deps, { squad: input.squad, viewer: input.member }),
    picked: true,
  };
}
