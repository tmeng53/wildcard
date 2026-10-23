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
import { latestAwardedWeek } from '@wildcard/weekly-awards';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const WEEK = 7 * 86_400_000;

const sceneField = Scene.meta({
  description: 'One of the scenes the app draws. More may come with an app release.',
  example: 'pool',
});

const SquadSceneBody = z
  .strictObject({
    version: bodyVersion(1),
    week: SceneWeek.meta({
      description:
        'The Monday of the week open for picking now: from Sunday 8pm Eastern, when a week’s ' +
        'awards are given, the week after it.',
      example: '2026-10-26',
    }),
    scene: sceneField.meta({ description: 'The squad’s scene this week.' }),
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
      .meta({ description: 'Every scene, in the order the picker shows them.' }),
  })
  .openapi('SquadScene');

const ScenePickBody = z
  .strictObject({ version: bodyVersion(1), scene: sceneField })
  .openapi('ScenePick');

function wire(scene: SquadScene) {
  return {
    version: 1 as const,
    week: scene.week,
    scene: scene.scene,
    pickers: { by: scene.pickers.by, members: [...scene.pickers.members] },
    picked:
      scene.picked === undefined
        ? null
        : {
            scene: scene.picked.scene,
            by: scene.picked.by,
            at: scene.picked.at.toISOString(),
          },
    canPick: scene.canPick,
    scenes: Scene.options.map((each) => ({
      scene: each,
      weeksAgo: scene.lastTrained.get(each) ?? null,
    })),
  };
}

/**
 * The week a squad picks its scene for at `moment`: the week after the latest one awarded.
 * The crown winner of a week picks the next.
 */
export function sceneWeekAt(moment: Date): SceneWeek {
  const awarded = latestAwardedWeek(moment);
  return SceneWeek.parse(new Date(Date.parse(awarded) + WEEK).toISOString().slice(0, 10));
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
  readonly clock: () => Date;
}) {
  const scenes = createSquadScenes({
    squads: deps.squads,
    clock: deps.clock,
    sceneWeekAt,
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
      'Last week’s crown winners pick the scene once a week, from Sunday 8pm Eastern when the ' +
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
        'Not a valid squad id, week or scene, or a week that isn’t open for picking ' +
          '(`SCENE_WEEK_CLOSED`)',
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
      const scene = await scenes.scene({
        squad: c.req.valid('param').squadId,
        viewer: MemberId.parse(c.var.caller.userId),
      });
      return c.json(wire(scene), 200);
    })
    .openapi(pick, async (c) => {
      const { squadId, weekStart } = c.req.valid('param');
      const { scene, picked } = await scenes.pick({
        squad: squadId,
        member: MemberId.parse(c.var.caller.userId),
        week: weekStart,
        scene: c.req.valid('json').scene,
      });
      return picked ? c.json(wire(scene), 201) : c.json(wire(scene), 200);
    });
}
