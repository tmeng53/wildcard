import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  CheckInDraft,
  CheckInId,
  DayRange,
  Disclaimer,
  LocalDay,
  Meal,
  MemberId,
  SquadId,
  Training,
  type CheckInRecord,
  type CheckIns,
} from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const checkInFields = {
  version: bodyVersion(1),
  id: z.uuid(),
  member: z.uuid().meta({ description: 'The member who made it.' }),
  day: LocalDay.meta({ description: 'The member’s local day it counts for.' }),
  createdAt: z.iso.datetime().meta({
    description: 'When the member made it, in UTC with milliseconds.',
    example: '2026-10-18T14:03:00.000Z',
  }),
  audience: z.array(z.uuid()).meta({
    description:
      'The squads it went to, in the member’s order. On someone else’s check-in, only the ' +
      'viewer’s own squads are listed.',
  }),
};

/** A saved check-in, as the app's contract has it (`CheckIn` in ios/Packages/Contracts). */
export const CheckIn = z
  .discriminatedUnion('kind', [
    z.strictObject({ ...checkInFields, kind: z.literal('trained'), training: Training }),
    z.strictObject({ ...checkInFields, kind: z.literal('healthyMeal'), meal: Meal }),
    z.strictObject({ ...checkInFields, kind: z.literal('cheatMeal'), meal: Meal }),
    z.strictObject({ ...checkInFields, kind: z.literal('disclaimer'), disclaimer: Disclaimer }),
  ])
  .openapi('CheckIn');

const CheckInList = z
  .strictObject({ version: bodyVersion(1), checkIns: z.array(CheckIn) })
  .openapi('CheckInList');

function wire(record: CheckInRecord) {
  const base = {
    version: 1 as const,
    id: record.id,
    member: record.member,
    day: record.day,
    createdAt: record.createdAt.toISOString(),
    audience: [...record.audience],
  };
  switch (record.kind) {
    case 'trained':
      return { ...base, kind: record.kind, training: record.training };
    case 'healthyMeal':
    case 'cheatMeal':
      return { ...base, kind: record.kind, meal: record.meal };
    case 'disclaimer':
      return { ...base, kind: record.kind, disclaimer: record.disclaimer };
  }
}

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/**
 * Daily check-ins: `PUT /check-ins/{id}` saves one, `GET /squads/{squadId}/check-ins` and
 * `GET /me/check-ins` read them back for a range of days.
 */
export function checkIns(deps: { readonly verifyToken: VerifyToken; readonly checkIns: CheckIns }) {
  const save = createRoute({
    method: 'put',
    path: '/check-ins/{id}',
    operationId: 'saveCheckIn',
    summary: 'Save a check-in',
    description:
      'The app makes the id, so a save can be retried: the same check-in again answers 200 ' +
      'with the saved one, different contents under a saved id answer 409.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({ id: CheckInId }),
      body: {
        required: true,
        content: { 'application/json': { schema: CheckInDraft.meta({ id: 'CheckInDraft' }) } },
      },
    },
    responses: {
      200: {
        description: 'Already saved: this was a retry',
        content: { 'application/json': { schema: CheckIn } },
      },
      201: { description: 'Saved', content: { 'application/json': { schema: CheckIn } } },
      400: problem(
        'Not a valid check-in, made more than 48 hours ago or ahead of the server’s clock, ' +
          'or counted for the wrong day',
      ),
      403: problem('Sent to a squad the member isn’t in'),
      409: problem('The id holds a different check-in, or today’s disclaimer is already posted'),
      ...signedInFailures,
    },
  });

  const listForSquad = createRoute({
    method: 'get',
    path: '/squads/{squadId}/check-ins',
    operationId: 'listSquadCheckIns',
    summary: 'A squad’s check-ins for a range of days',
    description:
      'Check-ins sent to the squad by members still in it, newest day first. Only for members ' +
      'of the squad.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId }), query: DayRange },
    responses: {
      200: {
        description: 'The check-ins',
        content: { 'application/json': { schema: CheckInList } },
      },
      400: problem('Not a valid range of days (at most 31)'),
      403: problem('The member isn’t in this squad'),
      ...signedInFailures,
    },
  });

  const listMine = createRoute({
    method: 'get',
    path: '/me/check-ins',
    operationId: 'listMyCheckIns',
    summary: 'The signed-in member’s check-ins for a range of days',
    description: 'Newest day first, each with its whole audience.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { query: DayRange },
    responses: {
      200: {
        description: 'The check-ins',
        content: { 'application/json': { schema: CheckInList } },
      },
      400: problem('Not a valid range of days (at most 31)'),
      ...signedInFailures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(save, async (c) => {
      const { checkIn, created } = await deps.checkIns.save({
        id: c.req.valid('param').id,
        member: MemberId.parse(c.var.caller.userId),
        draft: c.req.valid('json'),
      });
      return created ? c.json(wire(checkIn), 201) : c.json(wire(checkIn), 200);
    })
    .openapi(listForSquad, async (c) => {
      const records = await deps.checkIns.listForSquad({
        viewer: MemberId.parse(c.var.caller.userId),
        squad: c.req.valid('param').squadId,
        days: c.req.valid('query'),
      });
      return c.json({ version: 1 as const, checkIns: records.map(wire) }, 200);
    })
    .openapi(listMine, async (c) => {
      const records = await deps.checkIns.listMine({
        member: MemberId.parse(c.var.caller.userId),
        days: c.req.valid('query'),
      });
      return c.json({ version: 1 as const, checkIns: records.map(wire) }, 200);
    });
}
