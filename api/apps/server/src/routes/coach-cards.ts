import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  CARDS_DAYS,
  CoachCardId,
  CoachCardKind,
  STACK_HOURS,
  SquadId as CoachSquadId,
  cardKey,
  type Coach,
  type CoachActivity,
  type CoachOwnCard,
} from '@wildcard/coach';
import { MemberId as PushMember, type Push } from '@wildcard/push';
import { MemberId, SquadId, type Squads } from '@wildcard/squads';
import { MemberId as UnlockMember, type CoachGift, type CoachGifts } from '@wildcard/unlocks';

import { bodyVersion } from '../body-version.js';
import type { CoachNames } from '../flows/coach-names.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { CoachChallengeBody, CoachSpeakerBody, speakerIn } from './coach-activity.js';

// The coach page (Tracy, 2026-11-08): what the squad's coach said to the caller, a card a thing,
// stacked in the order it came; a card swiped away is seen and goes to 以前. The cards span
// modules: the coach's own (its 战术板 line, the caller's morning note and its challenge, its
// replies and answers to them) and the unlocks module's gifts.

const CoachCardBody = z
  .strictObject({
    kind: z.string().meta({
      description:
        '`board` (its 战术板 line), `note` (the morning note), `challenge` (今日挑战), `gift`, ' +
        '`reply` (its line to the caller’s check-in) or `answer` (to the caller’s reply). More ' +
        'kinds may come: an app skips a kind it doesn’t know.',
      example: 'challenge',
    }),
    id: z.string().meta({
      description:
        'The card’s id within its kind, which marking it seen names: a 战术板 line’s day, a ' +
        'note’s id (its challenge’s too), a gift’s piece, a reply’s or answer’s id.',
      example: '42',
    }),
    coach: CoachSpeakerBody,
    at: z.iso.datetime().meta({ description: 'When it came: a note when it was delivered.' }),
    day: z.iso.date().optional().meta({
      description: 'The squad’s day a `board`, `note` or `challenge` is for.',
    }),
    text: z.string().optional().meta({
      description: 'What the coach said, on a `board`, `note`, `reply` or `answer`.',
      example: '配速比上周快了，不错。',
    }),
    challenge: CoachChallengeBody.optional().meta({ description: 'A `challenge`’s challenge.' }),
    checkInId: z.uuid().optional().meta({
      description: 'The caller’s check-in a `reply` is on, or an `answer`’s post.',
    }),
    commentId: z.uuid().optional().meta({ description: 'The caller’s reply an `answer` answers.' }),
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
      description: `The cards not seen yet from the last ${String(STACK_HOURS)} hours, oldest first: the stack.`,
    }),
    earlier: z.array(CoachCardBody).meta({
      description: `Every other card from the last ${String(CARDS_DAYS)} days, newest first: 以前.`,
    }),
  })
  .openapi('CoachCards');

const CoachCardSeen = z
  .strictObject({ version: bodyVersion(1), kind: CoachCardKind, id: CoachCardId })
  .openapi('CoachCardSeen');

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
      return {
        ...base,
        day: card.day,
        challenge: {
          ...card.challenge,
          ...(card.answer === undefined ? {} : { answer: card.answer }),
        },
      };
    case 'reply':
      return { ...base, checkInId: card.checkIn, text: card.text };
    case 'answer':
      return { ...base, checkInId: card.checkIn, commentId: card.comment, text: card.text };
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
  /** The coaches on offer, for a gift's coach's look (a retired one's stands in as a silhouette). */
  readonly coachHiring: { offered(): Promise<readonly Coach[]> };
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
      'delivered (while their `coach` switch is on), its gifts, and its lines to their check-ins ' +
      'and replies. The unseen ones from ' +
      `the last ${String(STACK_HOURS)} hours are the stack; the rest are 以前.`,
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

  return new OpenAPIHono<SignedIn>()
    .openapi(read, async (c) => {
      const { squadId } = c.req.valid('param');
      const member = c.var.caller.userId;
      // Throws `SquadNotJoinedError` for anyone not in the squad.
      const squad = await deps.squads.find({ squad: squadId, viewer: MemberId.parse(member) });
      const now = new Date();
      const joined = squad.members.find((each) => String(each.member) === member)?.joinedAt;
      const back = new Date(now.getTime() - CARDS_DAYS * 24 * 60 * 60_000);
      const since = joined !== undefined && joined > back ? joined : back;
      const [{ cards: all, seen: seenKeys }, allGifts, coaches, notesOn] = await Promise.all([
        deps.coachActivity.cards({ squad: CoachSquadId.parse(squadId), member, since }),
        deps.gifts.of(UnlockMember.parse(member)),
        deps.coachHiring.offered().catch(() => []),
        // A switch that can't be read counts as off, so the rest of the cards still show.
        deps.push
          .settingsOf(PushMember.parse(member))
          .then((settings) => settings.coach)
          .catch(() => false),
      ]);
      const cards = notesOn
        ? all
        : all.filter((card) => card.kind !== 'note' && card.kind !== 'challenge');
      const gifts = allGifts.filter((gift) => gift.squad === squadId && gift.givenAt >= since);
      const named = await deps.coachNames(
        [...cards.map((card) => card.coach.id), ...gifts.map((gift) => gift.coach)].map(
          (coach) => ({ coach, squad: squadId }),
        ),
      );
      const speaker = speakerIn((coach) => named(coach, squadId));
      const byId = new Map<string, Coach>(coaches.map((coach) => [coach.id, coach]));
      const merged = [
        ...cards.map((card) => ({ at: card.at, wire: wireCard(card, speaker) })),
        ...gifts.map((gift) => ({
          at: gift.givenAt,
          wire: wireGift(gift, { coach: byId.get(gift.coach), speaker }),
        })),
      ].sort((a, b) => a.at.getTime() - b.at.getTime());
      const fresh = now.getTime() - STACK_HOURS * 60 * 60_000;
      const stacked = (card: (typeof merged)[number]) =>
        card.at.getTime() >= fresh &&
        !seenKeys.has(cardKey(CoachCardKind.parse(card.wire.kind), card.wire.id));
      return c.json(
        {
          version: 1 as const,
          stack: merged.filter(stacked).map(({ wire }) => wire),
          earlier: merged
            .filter((card) => !stacked(card))
            .reverse()
            .map(({ wire }) => wire),
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
