import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { SportId } from '@wildcard/sport-ids';
import { AFTER_MAX, ItemId, MemberId, PieceId, UnlockKind, type Unlocks } from '@wildcard/unlocks';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const Unlock = z
  .strictObject({
    kind: UnlockKind.exclude(['piece']).meta({
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

const reason = Unlock.shape.reason;

const PieceUnlock = z
  .strictObject({
    id: PieceId.meta({ description: 'The piece’s id in the app’s art.', example: 'lap-bib' }),
    unlockedAt: Unlock.shape.unlockedAt,
    reason,
  })
  .openapi('PieceUnlock');

const LockedPiece = z
  .strictObject({
    id: PieceId.meta({ description: 'The piece’s id in the app’s art.', example: 'lap-singlet' }),
    checkInsToGo: z
      .int()
      .min(1)
      .max(AFTER_MAX)
      .meta({ description: 'How many more 练了 check-ins in its sports open it.', example: 2 }),
  })
  .openapi('LockedPiece');

const MyUnlocks = z
  .strictObject({
    version: bodyVersion(1),
    unlocks: z.array(Unlock).meta({
      description: 'Every store and prop the member unlocked, the earliest first.',
    }),
    pieces: z.array(PieceUnlock).meta({
      description:
        'Every clothing piece the member unlocked, the earliest first. A piece with a rule ' +
        'stays locked in its store, even an open one, until then.',
    }),
    lockedPieces: z.array(LockedPiece).meta({
      description: 'Every piece with a rule the member hasn’t unlocked yet, and how far it is.',
    }),
  })
  .openapi('MyUnlocks');

/** `GET /me/unlocks`: the stores, props and pieces the signed-in member unlocked by training. */
export function unlocks(deps: { readonly verifyToken: VerifyToken; readonly unlocks: Unlocks }) {
  const route = createRoute({
    method: 'get',
    path: '/me/unlocks',
    operationId: 'getMyUnlocks',
    summary: 'The stores, props and pieces the signed-in member unlocked',
    description:
      'Stores on the character editor’s 商店街, props and clothing pieces open by 练了 ' +
      'check-ins in their sports, counting only those made since the rule was added. Starters ' +
      '(WARM-UP, the tumbler, the dumbbell and every piece without a rule) are everyone’s and ' +
      'never listed. An unlock is never taken back.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: { description: 'The unlocks', content: { 'application/json': { schema: MyUnlocks } } },
      401: problem('No bearer token, or not a valid one'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>().openapi(route, async (c) => {
    const { unlocks, locked } = await deps.unlocks.standing(MemberId.parse(c.var.caller.userId));
    const shown = (unlock: (typeof unlocks)[number]) => ({
      id: unlock.id,
      unlockedAt: unlock.unlockedAt.toISOString(),
      reason: { sports: [...unlock.sports], checkIns: unlock.after },
    });
    return c.json(
      {
        version: 1 as const,
        unlocks: unlocks.flatMap((unlock) =>
          unlock.kind === 'piece' ? [] : [{ kind: unlock.kind, ...shown(unlock) }],
        ),
        pieces: unlocks.filter(({ kind }) => kind === 'piece').map(shown),
        lockedPieces: locked
          .filter(({ kind }) => kind === 'piece')
          .map(({ id, toGo }) => ({ id, checkInsToGo: toGo })),
      },
      200,
    );
  });
}
