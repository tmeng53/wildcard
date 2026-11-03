import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { SportId } from '@wildcard/sport-ids';
import { AFTER_MAX, ItemId, MemberId, UnlockKind, type Unlocks } from '@wildcard/unlocks';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const Unlock = z
  .strictObject({
    kind: UnlockKind.meta({
      description: '`store` for a store on the character editor’s 商店街, `prop` for a prop.',
    }),
    id: ItemId.meta({
      description: 'The store’s or prop’s id in the app’s art.',
      example: 'deuce',
    }),
    unlockedAt: z.iso.datetime({ offset: true }).meta({
      description: 'When the member made the check-in that unlocked it.',
      example: '2026-11-03T18:30:00.000Z',
    }),
    reason: z
      .strictObject({
        sports: z.array(SportId).meta({
          description: 'The sports whose 练了 counted; empty for any sport.',
          example: ['tennis', 'pickleball', 'squash'],
        }),
        checkIns: z
          .int()
          .min(1)
          .max(AFTER_MAX)
          .meta({ description: 'How many 练了 check-ins in them it took.', example: 3 }),
      })
      .openapi('UnlockReason'),
  })
  .openapi('Unlock');

const MyUnlocks = z
  .strictObject({
    version: bodyVersion(1),
    unlocks: z.array(Unlock).meta({
      description: 'Every store and prop the member unlocked, the earliest first.',
    }),
  })
  .openapi('MyUnlocks');

/** `GET /me/unlocks`: the stores and props the signed-in member unlocked by training. */
export function unlocks(deps: { readonly verifyToken: VerifyToken; readonly unlocks: Unlocks }) {
  const route = createRoute({
    method: 'get',
    path: '/me/unlocks',
    operationId: 'getMyUnlocks',
    summary: 'The stores and props the signed-in member unlocked',
    description:
      'Stores on the character editor’s 商店街 and props open by 练了 check-ins in their ' +
      'sports, counting only those made since the rule was added. Starters (WARM-UP, the ' +
      'tumbler and the dumbbell) are everyone’s and never listed. An unlock is never taken back.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: { description: 'The unlocks', content: { 'application/json': { schema: MyUnlocks } } },
      401: problem('No bearer token, or not a valid one'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>().openapi(route, async (c) => {
    const unlocked = await deps.unlocks.of(MemberId.parse(c.var.caller.userId));
    return c.json(
      {
        version: 1 as const,
        unlocks: unlocked.map((unlock) => ({
          kind: unlock.kind,
          id: unlock.id,
          unlockedAt: unlock.unlockedAt.toISOString(),
          reason: { sports: [...unlock.sports], checkIns: unlock.after },
        })),
      },
      200,
    );
  });
}
