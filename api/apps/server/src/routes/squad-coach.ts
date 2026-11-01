import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { CoachId, MemberId as CoachMemberId, SquadId as CoachSquadId } from '@wildcard/coach';
import { NoCoachHiredError, type Coach, type CoachHiring } from '@wildcard/coach';
import { MemberId, NotSquadCaptainError, SquadId, type Squads } from '@wildcard/squads';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const coachIdField = z
  .string()
  .regex(/^[a-z][a-z0-9-]{1,39}$/)
  .meta({ description: 'The coach’s id. Never changes.', example: 'xiaohun' });

const CoachCardBody = z
  .strictObject({
    id: coachIdField,
    tier: z.enum(['entry', 'advanced', 'pro']).meta({
      description: '入门, 进阶 or 专业: a style a squad picks, never a better coach.',
    }),
    name: z.string().meta({ example: '毛头' }),
    title: z.string().meta({ description: 'Its 头衔, next to its name.', example: '混混教练' }),
    catchphrase: z.string().meta({ description: 'Its 口头禅.', example: '先动起来，证书以后再说' }),
    background: z.string().meta({ description: 'Its fictional 履历.' }),
    yearsCoaching: z.int().min(0).meta({ description: 'The number in 执教: its fictional years.' }),
    experience: z
      .string()
      .meta({ description: 'What 执教 says after the years.', example: '热情满格' }),
    style: z.string().meta({ description: 'Its 风格.', example: '懂行、松弛、风趣' }),
    tags: z.array(z.string()).meta({ description: 'The tags on its card in 教练市场.' }),
    pay: z.string().meta({ description: 'Its 期望待遇.', example: '管饭就行' }),
    look: z.string().meta({ description: 'The character the app draws, by the art’s id.' }),
  })
  .openapi('CoachCard');

const CoachMarketBody = z
  .strictObject({
    version: bodyVersion(1),
    coaches: z.array(CoachCardBody).meta({ description: 'The coaches a squad can hire now.' }),
  })
  .openapi('CoachMarket');

const SquadCoachBody = z
  .strictObject({
    version: bodyVersion(1),
    coach: CoachCardBody.nullable().meta({ description: 'The squad’s coach, or null for none.' }),
    since: z.iso
      .datetime()
      .nullable()
      .meta({ description: 'When the squad hired it (执教第 N 周 counts from here), or null.' }),
    canHire: z.boolean().meta({
      description: 'True for the captain, the only member who hires, changes and fires the coach.',
    }),
  })
  .openapi('SquadCoach');

const CoachHireBody = z
  .strictObject({ version: bodyVersion(1), coach: coachIdField })
  .openapi('CoachHire');

/** A coach as the app shows it: never its soul, which only the model reads. */
function card(coach: Coach) {
  return {
    id: coach.id,
    tier: coach.tier,
    name: coach.name,
    title: coach.title,
    catchphrase: coach.catchphrase,
    background: coach.background,
    yearsCoaching: coach.yearsCoaching,
    experience: coach.experience,
    style: coach.style,
    tags: [...coach.tags],
    pay: coach.pay,
    look: coach.look,
  };
}

/**
 * `GET /coaches` (教练市场) and `GET`, `PUT` and `DELETE /squads/{squadId}/coach` (the 教练 card in
 * 小队设置). It spans modules: the squads say who is in the squad and who its captain is, the
 * coach module keeps the coaches and each squad's hire.
 */
export function squadCoach(deps: {
  readonly verifyToken: VerifyToken;
  readonly squads: Squads;
  readonly coachHiring: CoachHiring;
}) {
  /** The squad, for one of its members; throws `SquadNotJoinedError` for anyone else. */
  const squadFor = async (squadId: SquadId, userId: string) => {
    const viewer = MemberId.parse(userId);
    const squad = await deps.squads.find({ squad: squadId, viewer });
    return { viewer, isCaptain: squad.captain === viewer };
  };
  const squadCoachOf = async (squadId: SquadId, isCaptain: boolean) => {
    const current = await deps.coachHiring.current(CoachSquadId.parse(squadId));
    return {
      version: 1 as const,
      coach: current === undefined ? null : card(current.coach),
      since: current === undefined ? null : current.since.toISOString(),
      canHire: isCaptain,
    };
  };

  const signedInFailures = {
    401: problem('No bearer token, or not a valid one'),
    503: problem('Sign-in can’t be checked right now'),
  };
  const squadCoachResponse = (description: string) => ({
    description,
    content: { 'application/json': { schema: SquadCoachBody } },
  });
  const params = z.strictObject({ squadId: SquadId });

  const market = createRoute({
    method: 'get',
    path: '/coaches',
    operationId: 'listCoaches',
    summary: 'The coaches a squad can hire (教练市场)',
    description: 'Every coach offered now, with its 简历. The same coaches for every squad.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: {
        description: 'The coaches',
        content: { 'application/json': { schema: CoachMarketBody } },
      },
      ...signedInFailures,
    },
  });

  const read = createRoute({
    method: 'get',
    path: '/squads/{squadId}/coach',
    operationId: 'getSquadCoach',
    summary: 'A squad’s coach',
    description: 'The coach the squad has hired, if any. Only for its members.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      200: squadCoachResponse('The squad’s coach'),
      400: problem('Not a valid squad id'),
      403: problem('The member isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      ...signedInFailures,
    },
  });

  const hire = createRoute({
    method: 'put',
    path: '/squads/{squadId}/coach',
    operationId: 'hireSquadCoach',
    summary: 'Hire the squad’s coach (招聘, 换教练)',
    description:
      'For the captain: hires an offered coach, firing the squad’s coach first when it has ' +
      'another (one step, both logged). The squad’s memory stays with the squad. Safe to repeat: ' +
      'the coach it has already answers 200.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params,
      body: { required: true, content: { 'application/json': { schema: CoachHireBody } } },
    },
    responses: {
      200: squadCoachResponse('The squad has this coach already: this was a retry'),
      201: squadCoachResponse('Hired'),
      400: problem(
        'Not a valid squad id or coach id, or a coach that isn’t offered (`COACH_NOT_OFFERED`)',
      ),
      403: problem(
        'The member isn’t in this squad (`SQUAD_NOT_JOINED`), or isn’t its captain ' +
          '(`NOT_SQUAD_CAPTAIN`)',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const fire = createRoute({
    method: 'delete',
    path: '/squads/{squadId}/coach',
    operationId: 'fireSquadCoach',
    summary: 'Fire the squad’s coach (解雇)',
    description:
      'For the captain. The squad’s memory stays with the squad for the next coach. Safe to ' +
      'repeat: a squad with no coach answers the same.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      200: squadCoachResponse('The squad has no coach now'),
      400: problem('Not a valid squad id'),
      403: problem(
        'The member isn’t in this squad (`SQUAD_NOT_JOINED`), or isn’t its captain ' +
          '(`NOT_SQUAD_CAPTAIN`)',
      ),
      ...signedInFailures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(market, async (c) => {
      const coaches = await deps.coachHiring.offered();
      return c.json({ version: 1 as const, coaches: coaches.map(card) }, 200);
    })
    .openapi(read, async (c) => {
      const { squadId } = c.req.valid('param');
      const { isCaptain } = await squadFor(squadId, c.var.caller.userId);
      return c.json(await squadCoachOf(squadId, isCaptain), 200);
    })
    .openapi(hire, async (c) => {
      const { squadId } = c.req.valid('param');
      const { viewer, isCaptain } = await squadFor(squadId, c.var.caller.userId);
      if (!isCaptain) throw new NotSquadCaptainError();
      const { changed } = await deps.coachHiring.change({
        squad: CoachSquadId.parse(squadId),
        coach: CoachId.parse(c.req.valid('json').coach),
        by: CoachMemberId.parse(viewer),
      });
      const body = await squadCoachOf(squadId, true);
      return changed ? c.json(body, 201) : c.json(body, 200);
    })
    .openapi(fire, async (c) => {
      const { squadId } = c.req.valid('param');
      const { viewer, isCaptain } = await squadFor(squadId, c.var.caller.userId);
      if (!isCaptain) throw new NotSquadCaptainError();
      const squad = CoachSquadId.parse(squadId);
      if ((await deps.coachHiring.current(squad)) !== undefined) {
        await deps.coachHiring.fire({ squad, by: CoachMemberId.parse(viewer) }).catch(
          // Fired by someone else meanwhile: the squad has no coach, as asked.
          (error: unknown) => {
            if (!(error instanceof NoCoachHiredError)) throw error;
          },
        );
      }
      return c.json(await squadCoachOf(squadId, true), 200);
    });
}
