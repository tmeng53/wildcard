import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { SportId } from '@wildcard/sport-ids';
import {
  AFTER_MAX,
  CoachId,
  ItemId,
  MemberId,
  PieceId,
  UnlockKind,
  type CoachGifts,
  type Unlocks,
} from '@wildcard/unlocks';

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
    sports: z.array(SportId).meta({
      description: 'The sports whose 练了 count towards it; empty for any sport.',
      example: ['run', 'walk'],
    }),
    checkInsToGo: z
      .int()
      .min(1)
      .max(AFTER_MAX)
      .meta({ description: 'How many more 练了 check-ins in its sports open it.', example: 2 }),
  })
  .openapi('LockedPiece');

const ShelfStore = z
  .strictObject({
    id: ItemId.meta({ description: 'The store’s id in the app’s art.', example: 'powder' }),
    open: z.boolean().meta({
      description:
        'Whether it is open now (its switch on). A closed store shows only what the member owns.',
    }),
  })
  .openapi('ShelfStore');

const ShelfPiece = z
  .strictObject({
    id: PieceId.meta({ description: 'The piece’s id in the app’s art.', example: 'powder-tuna' }),
    storeId: ItemId.meta({ description: 'The store it hangs in.', example: 'powder' }),
    state: z.enum(['owned', 'available', 'locked']).meta({
      description:
        '`owned` once unlocked or claimed (worn all year, whatever the switches), and for a ' +
        'limited store’s starter while it is out (claim it to keep it); `available` for any ' +
        'other starter that is out now, `locked` for one still to earn (a 「？」 box).',
    }),
    checkInsToGo: LockedPiece.shape.checkInsToGo.optional().meta({
      description: 'For a locked piece: how many more 练了 check-ins in its sports open it.',
    }),
    sports: z.array(SportId).meta({
      description: 'The sports whose 练了 count towards it; empty for any sport.',
      example: ['ski', 'snowboard'],
    }),
    checkIns: z
      .int()
      .min(0)
      .max(AFTER_MAX)
      .meta({ description: 'How many 练了 check-ins it takes; 0 for a starter.', example: 1 }),
  })
  .openapi('ShelfPiece');
const GiftedPiece = z
  .strictObject({
    id: PieceId.meta({ description: 'The piece’s id in the app’s art.', example: 'gift-scarf' }),
    coach: CoachId.meta({ description: 'The coach who gave it.', example: 'xiaohun' }),
    givenAt: z.iso.datetime({ offset: true }).meta({
      description: 'When the coach gave it.',
      example: '2026-11-04T18:30:00.000Z',
    }),
  })
  .openapi('GiftedPiece');

const PieceClaim = z
  .strictObject({
    id: PieceId.meta({ description: 'The piece’s id in the app’s art.', example: 'lap-bib' }),
    claimedAt: z.iso.datetime({ offset: true }).meta({
      description: 'When the member claimed it (领取) into their wardrobe.',
      example: '2026-11-04T18:30:00.000Z',
    }),
  })
  .openapi('PieceClaim');

const ClaimedPiece = z
  .strictObject({ version: bodyVersion(1), claim: PieceClaim })
  .openapi('ClaimedPiece');

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
    claimed: z.array(PieceClaim).meta({
      description:
        'Every piece the member claimed (领取) into their wardrobe, the earliest first. An ' +
        'unlocked piece waits in its store, marked new, until claimed.',
    }),
    gifts: z.array(GiftedPiece).meta({
      description:
        'Every piece a squad’s coach gave the member, the earliest first. No store sells these: ' +
        'they belong in the member’s wardrobe.',
    }),
    shelf: z
      .strictObject({
        stores: z.array(ShelfStore).meta({
          description: 'Every store on the 商店街, in its order, and whether it is open now.',
        }),
        pieces: z.array(ShelfPiece).meta({
          description:
            'Every piece the member may see now: what they own, and what is out in an open ' +
            'store they have earned. A piece left out is not shown.',
        }),
      })
      .meta({
        description:
          'The 商店街 as it stands for the member now, worked out by the server from the stores’, ' +
          'pieces’ and switches’ rows: the app draws it as it is.',
      })
      .openapi('Shelf'),
  })
  .openapi('MyUnlocks');

/** `GET /me/unlocks`: the stores, props and pieces the signed-in member unlocked by training. */
export function unlocks(deps: {
  readonly verifyToken: VerifyToken;
  readonly unlocks: Unlocks;
  readonly gifts: Pick<CoachGifts, 'of'>;
}) {
  const route = createRoute({
    method: 'get',
    path: '/me/unlocks',
    operationId: 'getMyUnlocks',
    summary: 'The stores, props and pieces the signed-in member unlocked',
    description:
      'Stores on the character editor’s 商店街, props and clothing pieces open by 练了 ' +
      'check-ins in their sports, counting only those made since the rule was added; pieces a ' +
      'squad’s coach gave come apart, in `gifts`. Starters ' +
      '(WARM-UP, the tumbler, the dumbbell and every piece without a rule) are everyone’s and ' +
      'never listed in `unlocks` or `pieces`. An unlock is never taken back. `shelf` is the ' +
      '商店街 as the member sees it now, each store and switch applied.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: { description: 'The unlocks', content: { 'application/json': { schema: MyUnlocks } } },
      401: problem('No bearer token, or not a valid one'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  const claim = createRoute({
    method: 'put',
    path: '/me/pieces/{pieceId}/claim',
    operationId: 'claimPiece',
    summary: 'Claim an unlocked piece into the signed-in member’s wardrobe',
    description:
      '领取: puts a piece the member unlocked in their wardrobe (我的衣橱), on every phone. Nothing ' +
      'is bought. Claiming it again answers with the first claim.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ pieceId: PieceId }) },
    responses: {
      200: { description: 'The claim', content: { 'application/json': { schema: ClaimedPiece } } },
      400: problem('Not a piece id, or a piece the member hasn’t unlocked (`PIECE_NOT_UNLOCKED`)'),
      401: problem('No bearer token, or not a valid one'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  const shownClaim = ({ piece, claimedAt }: { piece: string; claimedAt: Date }) => ({
    id: piece,
    claimedAt: claimedAt.toISOString(),
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(claim, async (c) => {
      const kept = await deps.unlocks.claim(
        MemberId.parse(c.var.caller.userId),
        PieceId.parse(c.req.valid('param').pieceId),
      );
      return c.json({ version: 1 as const, claim: shownClaim(kept) }, 200);
    })
    .openapi(route, async (c) => {
      const member = MemberId.parse(c.var.caller.userId);
      const [{ unlocks, locked, shelf }, claims, gifts] = await Promise.all([
        deps.unlocks.standing(member),
        deps.unlocks.claimsOf(member),
        deps.gifts.of(member),
      ]);
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
            .map(({ id, toGo, sports }) => ({ id, sports: [...sports], checkInsToGo: toGo })),
          claimed: claims.map(shownClaim),
          gifts: gifts.map(({ piece, coach, givenAt }) => ({
            id: piece,
            coach,
            givenAt: givenAt.toISOString(),
          })),
          shelf: {
            stores: [...shelf.stores],
            pieces: shelf.pieces.map(({ toGo, sports, after, ...piece }) => ({
              ...piece,
              ...(toGo === undefined ? {} : { checkInsToGo: toGo }),
              sports: [...sports],
              checkIns: after,
            })),
          },
        },
        200,
      );
    });
}
