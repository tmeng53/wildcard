import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { WeekStart, type CheckIns } from '@wildcard/check-ins';
import {
  MemberId,
  Scene,
  SceneWeek,
  SquadId,
  createSquadScenes,
  type SquadScene,
  type Squads,
} from '@wildcard/squads';
import type { Scenes } from '@wildcard/scenes';
import { MemberId as NoticeMember, SquadId as NoticeSquad, type Notices } from '@wildcard/notices';
import { NEW_YORK } from '@wildcard/time-zones';
import {
  awardsTimeOf,
  weeksMaybeAwarded,
  type WeekStart as AwardsWeek,
} from '@wildcard/weekly-awards';

import { bodyVersion } from '../body-version.js';
import { LEGACY_SCENES, LegacyScene, legacyScene } from '../legacy-scene.js';
import type { Log } from '../log.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const WEEK = 7 * 86_400_000;

const sceneField = LegacyScene.meta({
  description:
    'The scene, for builds that know only the first five: one added since is sent as `gym`. ' +
    'Newer builds read `sceneId`.',
  example: 'pool',
});

const sceneIdField = Scene.meta({
  description:
    'The scene’s id in the scenes list (`GET /public/catalog`, `scenes`). The app draws the gym ' +
    'for one it has no art for.',
  example: 'ski',
});

const SquadSceneBody = z
  .strictObject({
    version: bodyVersion(1),
    week: SceneWeek.meta({
      description:
        'The Monday of the week open for picking now: from Sunday 8pm on the squad’s clock (小队时区), when a week’s ' +
        'awards are given, the week after it.',
      example: '2026-10-26',
    }),
    scene: sceneField.meta({ description: 'The squad’s scene this week (see `sceneId`).' }),
    sceneId: sceneIdField.meta({
      description:
        'The scene the squad’s home shows now: its scene this week, or, while a takeover scene ' +
        '(a holiday’s, say) is on, that one for every squad. `picked` is still the squad’s own.',
    }),
    takeover: z.boolean().meta({
      description:
        'True while `sceneId` is a takeover scene standing in for the squad’s own: the app plays ' +
        'its opening (the art at `openings/<sceneId>/`, if there is one) the first time it shows ' +
        'it each day, then drops the squad onto it.',
    }),
    pickers: z
      .strictObject({
        by: z.enum(['crown', 'captain']).meta({
          description:
            '`crown`: last week’s crown winners (皇冠) pick; `captain`: nobody won it, so the ' +
            'captain picks.',
        }),
        members: z.array(z.uuid()).meta({ description: 'Who may pick, in the order they joined.' }),
      })
      .meta({ description: 'Who picks this week’s scene, once.' }),
    picked: z
      .strictObject({
        scene: sceneField,
        sceneId: sceneIdField,
        by: z
          .uuid()
          .nullable()
          .meta({ description: 'Null once the picker deleted their account.' }),
        at: z.iso.datetime(),
      })
      .nullable()
      .meta({ description: 'This week’s pick, once made; it can’t be changed.' }),
    canPick: z.boolean().meta({
      description: 'True when the caller may pick now: one of the pickers, and nothing picked yet.',
    }),
    scenes: z
      .array(
        z.strictObject({
          scene: sceneField,
          weeksAgo: z
            .int()
            .min(0)
            .nullable()
            .meta({
              description:
                'How many weeks ago the squad last trained on it: 0 for this week’s scene, null ' +
                'for one it never has (the app shows it in its carton).',
            }),
        }),
      )
      .meta({
        description:
          'The first five scenes, in the order the picker shows them, for builds that know only ' +
          'those. Newer builds read `options`.',
      }),
    options: z
      .array(
        z.strictObject({
          sceneId: sceneIdField,
          weeksAgo: z
            .int()
            .min(0)
            .nullable()
            .meta({
              description:
                'How many weeks ago the squad last trained on it: 0 for this week’s scene, null ' +
                'for one it never has (the app shows it in its carton).',
            }),
        }),
      )
      .meta({
        description:
          'The scenes a pick may name this week, in the picker’s order: a limited one (the ' +
          'winter 雪场) only while it is open.',
      }),
  })
  .openapi('SquadScene');

const ScenePickBody = z
  .strictObject({
    version: bodyVersion(1),
    scene: Scene.meta({
      description: 'The scene’s id: one of `options` in `GET /squads/{squadId}/scene`.',
      example: 'pool',
    }),
  })
  .openapi('ScenePick');

/** The reply; `shown` is a takeover scene every home shows in place of the squad's, if one is on. */
function wire(scene: SquadScene, shown: string = scene.scene) {
  return {
    version: 1 as const,
    week: scene.week,
    scene: legacyScene(shown),
    sceneId: shown,
    takeover: shown !== scene.scene,
    pickers: { by: scene.pickers.by, members: [...scene.pickers.members] },
    picked:
      scene.picked === undefined
        ? null
        : {
            scene: legacyScene(scene.picked.scene),
            sceneId: scene.picked.scene,
            by: scene.picked.by,
            at: scene.picked.at.toISOString(),
          },
    canPick: scene.canPick,
    scenes: LEGACY_SCENES.map((each) => ({
      scene: each,
      weeksAgo: scene.lastTrained.get(each) ?? null,
    })),
    options: scene.open.map((each) => ({
      sceneId: each,
      weeksAgo: scene.lastTrained.get(each) ?? null,
    })),
  };
}

/**
 * The week a squad picks its scene for at `moment`: the week after the latest one awarded, each
 * week on its own clock (小队时区, which a captain's change may move between weeks). The crown
 * winner of a week picks the next.
 */
export function sceneWeekAt(moment: Date, zoneOf: (week: AwardsWeek) => string): SceneWeek {
  const weeks = weeksMaybeAwarded(moment);
  const awarded =
    weeks.findLast((week) => awardsTimeOf(week, zoneOf(week)) <= moment) ?? weeks[0] ?? never();
  return SceneWeek.parse(new Date(Date.parse(awarded) + WEEK).toISOString().slice(0, 10));
}

function never(): never {
  throw new Error('No week may be awarded.');
}

/**
 * `GET /squads/{squadId}/scene` and `PUT /squads/{squadId}/weeks/{weekStart}/scene`: the squad's
 * scene (小队设置, the 战报's last page). It spans modules: the squads keep the picks, the
 * check-ins' week summary names last week's crown, and the awards' clock says which week is open.
 */
export function squadScene(deps: {
  readonly verifyToken: VerifyToken;
  readonly squads: Squads;
  readonly checkIns: CheckIns;
  /** Which scenes are open in a week. */
  readonly scenes: Pick<Scenes, 'openOn'>;
  /**
   * The takeover scene `member`'s home shows now in place of the squad's (a scene on a switch,
   * as that member sees the switches), if one is on.
   */
  readonly takeoverFor: (member: string) => Promise<string | undefined>;
  /** Where the move is kept for the squadmates' 通知. */
  readonly notices: Notices;
  readonly clock: () => Date;
  readonly log: Log;
}) {
  const scenes = createSquadScenes({
    squads: deps.squads,
    clock: deps.clock,
    sceneWeekAt: async (moment, squad) => {
      const zones = new Map<string, string>();
      for (const week of weeksMaybeAwarded(moment)) {
        zones.set(week, (await deps.squads.timeZonesFor([squad], week)).get(squad) ?? NEW_YORK);
      }
      return sceneWeekAt(moment, (week) => zones.get(week) ?? NEW_YORK);
    },
    openScenes: (week) => deps.scenes.openOn(week),
    crownHolders: async ({ squad, week, viewer }) => {
      const summary = await deps.checkIns.weekSummary({
        squad,
        viewer,
        weekStart: WeekStart.parse(week),
      });
      const crown = summary.awards.find(({ kind }) => kind === 'crown');
      return (crown?.winners ?? []).map(({ member }) => MemberId.parse(member));
    },
  });

  const sceneResponse = (description: string) => ({
    description,
    content: { 'application/json': { schema: SquadSceneBody } },
  });
  const signedInFailures = {
    401: problem('No bearer token, or not a valid one'),
    503: problem('Sign-in can’t be checked right now'),
  };

  const read = createRoute({
    method: 'get',
    path: '/squads/{squadId}/scene',
    operationId: 'getSquadScene',
    summary: 'A squad’s scene this week, and who picks it',
    description:
      'Last week’s crown winners pick the scene once a week, from Sunday 8pm on the squad’s clock (小队时区) when the ' +
      'week is awarded; when nobody won the crown, the captain picks. A squad trains on its ' +
      'latest pick until the next one, and on the gym before its first. Only for its members.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId }) },
    responses: {
      200: sceneResponse('The scene'),
      400: problem('Not a valid squad id'),
      403: problem('The member isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      ...signedInFailures,
    },
  });

  const pick = createRoute({
    method: 'put',
    path: '/squads/{squadId}/weeks/{weekStart}/scene',
    operationId: 'pickSquadScene',
    summary: 'Pick the squad’s scene for the week',
    description:
      'Once a week, by one of `pickers` (`GET /squads/{squadId}/scene`), for the week open now. ' +
      'The pick takes effect at once and can’t be changed. Safe to repeat: the same pick by the ' +
      'same member again answers 200.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({
        squadId: SquadId,
        weekStart: SceneWeek.meta({ description: 'The week’s Monday.', example: '2026-10-26' }),
      }),
      body: { required: true, content: { 'application/json': { schema: ScenePickBody } } },
    },
    responses: {
      200: sceneResponse('Already picked: this was a retry'),
      201: sceneResponse('Picked'),
      400: problem(
        'Not a valid squad id, week or scene, a week that isn’t open for picking ' +
          '(`SCENE_WEEK_CLOSED`), or a scene that isn’t open this week (`SCENE_NOT_OPEN`)',
      ),
      403: problem(
        'The member isn’t in this squad (`SQUAD_NOT_JOINED`), or isn’t one of this week’s ' +
          'pickers (`NOT_SCENE_PICKER`)',
      ),
      409: problem('Someone already picked this week’s scene (`SCENE_ALREADY_PICKED`)'),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(read, async (c) => {
      const viewer = MemberId.parse(c.var.caller.userId);
      const [scene, takeover] = await Promise.all([
        scenes.scene({ squad: c.req.valid('param').squadId, viewer }),
        deps.takeoverFor(viewer),
      ]);
      return c.json(wire(scene, takeover), 200);
    })
    .openapi(pick, async (c) => {
      const { squadId, weekStart } = c.req.valid('param');
      const member = MemberId.parse(c.var.caller.userId);
      const { scene, picked } = await scenes.pick({
        squad: squadId,
        member,
        week: weekStart,
        scene: c.req.valid('json').scene,
      });
      if (picked)
        await tellMoved({ ...deps, squad: squadId, by: member, scene: c.req.valid('json').scene });
      const shown = wire(scene, await deps.takeoverFor(member));
      return picked ? c.json(shown, 201) : c.json(shown, 200);
    });
}

/**
 * Tells every squadmate but the picker that the squad moved (通知). After the pick, and never
 * undoing it: a notice that can't be kept is logged.
 */
async function tellMoved(deps: {
  readonly squads: Squads;
  readonly notices: Notices;
  readonly log: Log;
  readonly squad: SquadId;
  readonly by: MemberId;
  readonly scene: string;
}): Promise<void> {
  try {
    const members = await deps.squads.membersOf(deps.squad);
    await deps.notices.tell(
      members
        .filter((member) => member !== deps.by)
        .map((member) => ({
          member: NoticeMember.parse(member),
          squad: NoticeSquad.parse(deps.squad),
          kind: 'sceneMoved' as const,
          subject: { version: 1 as const, scene: deps.scene, by: NoticeMember.parse(deps.by) },
        })),
    );
  } catch (error) {
    deps.log.warn('scene move not kept in notices', { squad: deps.squad, error });
  }
}
