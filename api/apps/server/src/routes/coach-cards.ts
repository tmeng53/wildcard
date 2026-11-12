import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  CARDS_DAYS,
  CoachCardId,
  CoachCardKind,
  SquadId as CoachSquadId,
  cardKey,
  type Coach,
  type CoachActivity,
  type CoachHiring,
  type CoachOwnCard,
} from '@wildcard/coach';
import { MemberId as PushMember, type Push } from '@wildcard/push';
import { MemberId, SquadId, type Squads } from '@wildcard/squads';
import { momentAt, wallClockAt } from '@wildcard/time-zones';
import { MemberId as UnlockMember, type CoachGift, type CoachGifts } from '@wildcard/unlocks';

import { bodyVersion } from '../body-version.js';
import type { CoachNames } from '../flows/coach-names.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import {
  CoachChallengeBody,
  CoachSpeakerBody,
  speakerIn,
  wireChallenge,
} from './coach-activity.js';

// The coach page (Tracy, 2026-11-08): what the squad's coach said to the caller, a card a thing,
// stacked in the order it came; a card swiped away is seen and goes to 以前. The cards span
// modules: the coach's own (its 战术板 line, the caller's morning note and its challenge) and the
// unlocks module's gifts. Its lines to the caller's check-ins and replies show only under the
// posts in 动态 (Tracy, 2026-11-09).

const CoachCardBody = z
  .strictObject({
    kind: z.string().meta({
      description:
        '`board` (its 战术板 line), `note` (the morning note), `challenge` (今日挑战), ' +
        '`challengeDone` (the coach marked that challenge done from the caller’s check-ins), ' +
        'or `gift`. Its lines to the caller’s check-ins and replies show only under the posts. ' +
        'More kinds may come: an app skips a kind it doesn’t know.',
      example: 'challenge',
    }),
    id: z.string().meta({
      description:
        'The card’s id within its kind, which marking it seen names: a 战术板 line’s day, a ' +
        'note’s id (its challenge’s and `challengeDone`’s too) or a gift’s piece.',
      example: '42',
    }),
    coach: CoachSpeakerBody,
    at: z.iso.datetime().meta({
      description: 'When it came: a note when it was delivered, a `challengeDone` when marked.',
    }),
    day: z.iso.date().optional().meta({
      description: 'The squad’s day a `board`, `note`, `challenge` or `challengeDone` is for.',
    }),
    text: z.string().optional().meta({
      description: 'What the coach said, on a `board` or `note`.',
      example: '配速比上周快了，不错。',
    }),
    challenge: CoachChallengeBody.optional().meta({
      description: 'A `challenge`’s or `challengeDone`’s challenge.',
    }),
    gift: z
      .strictObject({
        pieceId: z.string().meta({ description: 'The piece, by the art’s id.' }),
        line: z.string().optional().meta({ description: 'What the coach said with it.' }),
        openedAt: z.iso.datetime().optional().meta({
          description: 'When the caller opened it (拆开); left out while it waits boxed.',
        }),
        worn: z.boolean().optional().meta({
          description: 'Whether they put it on when they opened it; only once opened.',
        }),
      })
      .optional()
      .meta({ description: 'A `gift`’s piece; open it with `PUT /me/gifts/{pieceId}/open`.' }),
  })
  .openapi('CoachPageCard');

const CoachCardsBody = z
  .strictObject({
    version: bodyVersion(1),
    stack: z.array(CoachCardBody).meta({
      description:
        'The cards not seen yet from today on the squad’s clock, oldest first: the stack.',
    }),
    earlier: z.array(CoachCardBody).meta({
      description: `Every other card from the last ${String(CARDS_DAYS)} days, newest first: 以前.`,
    }),
  })
  .openapi('CoachCards');

const CoachCardSeen = z
  .strictObject({
    version: bodyVersion(1),
    kind: z.string().meta({
      description: 'The card’s kind, as asked; more kinds may come.',
      example: 'challenge',
    }),
    id: CoachCardId,
  })
  .openapi('CoachCardSeen');

/** How many cards a page of 以前 holds. */
const EARLIER_PAGE = 20;

const EarlierCursor = z
  .string()
  .regex(/^\d{1,15}~[A-Za-z]{1,16}:[A-Za-z0-9_.:-]{1,64}$/)
  .meta({ description: 'The `next` of the page before.', example: '1794193129000~note:42' });

const EarlierCardsBody = z
  .strictObject({
    version: bodyVersion(1),
    cards: z.array(
      CoachCardBody.extend({
        seen: z.boolean().meta({ description: 'Whether the caller has seen it.' }),
      }),
    ),
    next: EarlierCursor.optional().meta({
      description: 'The cursor for the page after this one; left out on the last page.',
    }),
  })
  .openapi('EarlierCoachCards');

/** The cursor after a card: when it came, and its key to tell apart cards of one moment. */
function cursorOf(card: { readonly at: Date; readonly key: string }): string {
  return `${String(card.at.getTime())}~${card.key}`;
}

function parseCursor(cursor: string): { readonly at: number; readonly key: string } {
  const [at = '0', key = ''] = cursor.split('~');
  return { at: Number(at), key };
}

type Speaker = ReturnType<typeof speakerIn>;

/** A card as the app reads it. */
function wireCard(card: CoachOwnCard, speaker: Speaker): z.infer<typeof CoachCardBody> {
  const base = {
    kind: card.kind,
    id: card.id,
    coach: speaker(card.coach),
    at: card.at.toISOString(),
  };
  switch (card.kind) {
    case 'board':
    case 'note':
      return { ...base, day: card.day, text: card.text };
    case 'challenge':
      return { ...base, day: card.day, challenge: wireChallenge(card) };
    case 'challengeDone':
      return { ...base, day: card.day, challenge: card.challenge };
  }
}

function wireGift(
  gift: CoachGift,
  { coach, speaker }: { coach: Coach | undefined; speaker: Speaker },
) {
  return {
    kind: 'gift',
    id: gift.piece,
    coach: speaker({ id: gift.coach, name: coach?.name ?? gift.coach, look: coach?.look ?? '' }),
    at: gift.givenAt.toISOString(),
    gift: {
      pieceId: gift.piece,
      ...(gift.line === undefined ? {} : { line: gift.line }),
      ...(gift.opened === undefined
        ? {}
        : { openedAt: gift.opened.at.toISOString(), worn: gift.opened.worn }),
    },
  };
}

/**
 * `GET /squads/{squadId}/coach/cards` and marking one seen: the coach page's stack and 以前.
 */
export function coachCards(deps: {
  readonly verifyToken: VerifyToken;
  readonly squads: Squads;
  readonly coachActivity: CoachActivity;
  readonly gifts: Pick<CoachGifts, 'of'>;
  /**
   * The coaches on offer, for a gift's coach's look (a retired one's stands in as a silhouette),
   * and the squad's coach now, whose cards alone are the stack.
   */
  readonly coachHiring: Pick<CoachHiring, 'offered' | 'current'>;
  readonly coachNames: CoachNames;
  /** The caller's `coach` switch: switched off, no morning note or challenge shows (Tracy, 2026-11-07). */
  readonly push: Pick<Push, 'settingsOf'>;
}) {
  const read = createRoute({
    method: 'get',
    path: '/squads/{squadId}/coach/cards',
    operationId: 'getCoachCards',
    summary: 'What the squad’s coach said to the caller, as cards (the coach page)',
    description:
      'A card for each thing the squad’s coach said to the caller since they joined, up to ' +
      `${String(CARDS_DAYS)} days back: its 战术板 lines, their morning notes and challenges once ` +
      'delivered (while their `coach` switch is on) and its gifts. Its lines to their check-ins ' +
      'and replies show only under the posts. The unseen ones from ' +
      'today (on the squad’s clock) from the coach the squad has now are the stack; ' +
      'the rest, a coach’s that left too, are 以前.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId }) },
    responses: {
      200: {
        description: 'The stack and 以前',
        content: { 'application/json': { schema: CoachCardsBody } },
      },
      400: problem('Not a valid squad id'),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  const seen = createRoute({
    method: 'put',
    path: '/squads/{squadId}/coach/cards/{kind}/{cardId}/seen',
    operationId: 'markCoachCardSeen',
    summary: 'Mark one of the coach’s cards seen (swiped into 以前)',
    description:
      'The caller swiped the card away: it leaves the stack on every phone and stays in 以前. A ' +
      'seen `note` is also put away (收下) on 今天. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({ squadId: SquadId, kind: CoachCardKind, cardId: CoachCardId }),
    },
    responses: {
      200: {
        description: 'Seen',
        content: { 'application/json': { schema: CoachCardSeen } },
      },
      400: problem(
        'Not a valid squad id or card kind, or not an id of that kind (`COACH_CARD_ID_INVALID`)',
      ),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  const earlierRoute = createRoute({
    method: 'get',
    path: '/squads/{squadId}/coach/cards/earlier',
    operationId: 'getEarlierCoachCards',
    summary: 'The coach page’s 以前, a page at a time',
    description:
      'The cards that aren’t in the stack, newest first, as `GET …/coach/cards` has them, ' +
      `${String(EARLIER_PAGE)} at a time: pass the reply’s \`next\` as \`cursor\` for the page after ` +
      'it. `unseen` keeps only the cards the caller hasn’t seen (a coach’s that left, or older ' +
      'than today); each card says whether it was seen. `challenges` keeps ' +
      'only the challenges, every one since the caller joined, those in the stack too (挑战, ' +
      'Tracy 2026-11-09).',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({ squadId: SquadId }),
      query: z.strictObject({
        cursor: EarlierCursor.optional(),
        unseen: z.enum(['true', 'false']).optional().meta({
          description: '`true` keeps only the cards not seen yet.',
        }),
        challenges: z
          .enum(['true', 'false'])
          .optional()
          .meta({
            description: `\`true\` keeps only the challenges, from when the caller joined (not only the last ${String(CARDS_DAYS)} days).`,
          }),
      }),
    },
    responses: {
      200: {
        description: 'A page of 以前',
        content: { 'application/json': { schema: EarlierCardsBody } },
      },
      400: problem('Not a valid squad id or cursor'),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  /**
   * Every card for the caller in the squad, oldest first, each knowing whether it is stacked:
   * from the last `CARDS_DAYS` days, or `sinceJoined`, from whenever they joined.
   */
  async function sorted({
    squadId,
    member,
    sinceJoined = false,
  }: {
    squadId: z.infer<typeof SquadId>;
    member: string;
    sinceJoined?: boolean;
  }) {
    // Throws `SquadNotJoinedError` for anyone not in the squad.
    const squad = await deps.squads.find({ squad: squadId, viewer: MemberId.parse(member) });
    const now = new Date();
    const joined = squad.members.find((each) => String(each.member) === member)?.joinedAt;
    const back = new Date(now.getTime() - CARDS_DAYS * 24 * 60 * 60_000);
    const since = sinceJoined
      ? (joined ?? new Date(0))
      : joined !== undefined && joined > back
        ? joined
        : back;
    const [{ cards: all, seen: seenKeys }, allGifts, coaches, notesOn, hired] = await Promise.all([
      deps.coachActivity.cards({ squad: CoachSquadId.parse(squadId), member, since }),
      deps.gifts.of(UnlockMember.parse(member)),
      deps.coachHiring.offered().catch(() => []),
      // A switch that can't be read counts as off, so the rest of the cards still show.
      deps.push
        .settingsOf(PushMember.parse(member))
        .then((settings) => settings.coach)
        .catch(() => false),
      deps.coachHiring.current(CoachSquadId.parse(squadId)),
    ]);
    const cards = notesOn
      ? all
      : all.filter(
          (card) =>
            card.kind !== 'note' && card.kind !== 'challenge' && card.kind !== 'challengeDone',
        );
    const gifts = allGifts.filter((gift) => gift.squad === squadId && gift.givenAt >= since);
    const named = await deps.coachNames(
      [...cards.map((card) => card.coach.id), ...gifts.map((gift) => gift.coach)].map((coach) => ({
        coach,
        squad: squadId,
      })),
    );
    const speaker = speakerIn((coach) => named(coach, squadId));
    const byId = new Map<string, Coach>(coaches.map((coach) => [coach.id, coach]));
    // Only today's stack (Tracy, 2026-11-12): a card left unseen yesterday waits in 以前, so the
    // stack never piles up. Today is the squad's, as the morning note's day is.
    const zone = (await deps.squads.timeZonesAt([squad.id], now))(squad.id);
    const fresh = momentAt({ day: wallClockAt(now, zone).day, hour: 0, zone }).getTime();
    return (
      [
        ...cards.map((card) => ({
          at: card.at,
          coach: card.coach.id,
          wire: wireCard(card, speaker),
        })),
        ...gifts.map((gift) => ({
          at: gift.givenAt,
          coach: gift.coach,
          wire: wireGift(gift, { coach: byId.get(gift.coach), speaker }),
        })),
      ]
        .map((card) => {
          const key = cardKey(CoachCardKind.parse(card.wire.kind), card.wire.id);
          const seen = seenKeys.has(key);
          // A coach that left goes to 以前 whole, its boxed gifts still opening there (Tracy,
          // 2026-11-09): the stack is the coach the squad has now.
          const stacked = card.coach === hired?.coach.id && card.at.getTime() >= fresh && !seen;
          return { ...card, key, seen, stacked };
        })
        // Stable, so cards of one moment keep the store's order (a note before its challenge).
        .sort((a, b) => a.at.getTime() - b.at.getTime())
    );
  }

  return new OpenAPIHono<SignedIn>()
    .openapi(read, async (c) => {
      const { squadId } = c.req.valid('param');
      const cards = await sorted({ squadId, member: c.var.caller.userId });
      return c.json(
        {
          version: 1 as const,
          stack: cards.filter((card) => card.stacked).map(({ wire }) => wire),
          earlier: cards
            .filter((card) => !card.stacked)
            .reverse()
            .map(({ wire }) => wire),
        },
        200,
      );
    })
    .openapi(earlierRoute, async (c) => {
      const { squadId } = c.req.valid('param');
      const { cursor, unseen, challenges } = c.req.valid('query');
      const onlyChallenges = challenges === 'true';
      const listed = (
        await sorted({ squadId, member: c.var.caller.userId, sinceJoined: onlyChallenges })
      )
        .filter((card) => (onlyChallenges ? card.wire.kind === 'challenge' : !card.stacked))
        .reverse();
      const shown = (card: (typeof listed)[number]) => unseen !== 'true' || !card.seen;
      // The page starts after the card the cursor names. Found in the whole list, so one seen since
      // the last page (and so out of 未读) still marks the place; a card no longer listed at all
      // places it by its time.
      const after = cursor === undefined ? undefined : parseCursor(cursor);
      const named = after === undefined ? -1 : listed.findIndex((card) => card.key === after.key);
      const start =
        after === undefined
          ? 0
          : named >= 0
            ? named + 1
            : listed.findIndex((card) => card.at.getTime() < after.at);
      const newestFirst = start < 0 ? [] : listed.slice(start).filter(shown);
      const page = newestFirst.slice(0, EARLIER_PAGE);
      const last = page.at(-1);
      const more = newestFirst.length > EARLIER_PAGE;
      return c.json(
        {
          version: 1 as const,
          cards: page.map(({ wire, seen }) => ({ ...wire, seen })),
          ...(more && last !== undefined ? { next: cursorOf(last) } : {}),
        },
        200,
      );
    })
    .openapi(seen, async (c) => {
      const { squadId, kind, cardId } = c.req.valid('param');
      const member = c.var.caller.userId;
      await deps.squads.find({ squad: squadId, viewer: MemberId.parse(member) });
      await deps.coachActivity.markSeen({
        squad: CoachSquadId.parse(squadId),
        member,
        kind,
        id: cardId,
      });
      return c.json({ version: 1 as const, kind, id: cardId }, 200);
    });
}
