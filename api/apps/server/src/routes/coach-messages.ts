import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  ButtonId,
  CardPath,
  MemberId as MessageMember,
  MessageId,
  SquadId as MessageSquad,
  TEXT_LIMIT,
  cardsOf,
  type AnswerPart,
  type Answered,
  type AnyCard,
  type AnyStep,
  type CoachMessages,
  type MessageValue,
} from '@wildcard/coach-messages';
import { MemberId, SquadId, type Squads } from '@wildcard/squads';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { LocalizedWords } from './notices.js';

// 教练消息卡 (Tracy, 2026-11-12): a card admins put on members' coach pages, said by the squad's
// coach with no model writing it. On the wire its cards are listed flat, each by its path (the
// buttons tapped to reach it), and a button's `next` names the path it turns into, so the shape
// has no recursion. Kinds and styles are plain strings: an app skips a step it doesn't know.

const WirePath = z.string().meta({
  description:
    'Which card of the message: `` for the first, else the ids of the buttons tapped to reach ' +
    'it, joined by `.` (`no`, `no.send`).',
  example: 'no',
});

const MessageStepBody = z
  .strictObject({
    open: z
      .string()
      .optional()
      .meta({
        description:
          'Opens this: a page in the app by its address (as a `wildcard://` link would) or an ' +
          'https web page.',
        example: 'store/powder',
      }),
    feedback: z
      .string()
      .optional()
      .meta({
        description:
          'Sends what was typed in the card’s box as 意见反馈 (`POST /feedback`), as this kind: ' +
          '`problem` or `idea`.',
        example: 'problem',
      }),
    close: z.boolean().optional().meta({ description: '`true`: folds the card to its `thanks`.' }),
    next: WirePath.optional().meta({ description: 'Turns the card into the card at this path.' }),
  })
  .meta({ description: 'One step, exactly one of its fields set; skip a step you don’t know.' })
  .openapi('CoachMessageStep');

const MessageButtonBody = z
  .strictObject({
    id: z.string().meta({ description: 'Its id within its card.', example: 'yes' }),
    label: LocalizedWords,
    icon: z.string().optional().meta({ description: 'An SF Symbol before the words.' }),
    style: z.string().meta({
      description: '`primary` (graphite), `outline` or `plain` (words only); more may come.',
      example: 'outline',
    }),
    tap: z.array(MessageStepBody).meta({ description: 'What a tap does, step by step.' }),
  })
  .openapi('CoachMessageButton');

const MessageCardBody = z
  .strictObject({
    path: WirePath,
    line: LocalizedWords,
    body: LocalizedWords.optional(),
    about: z
      .strictObject({
        icon: z.string().optional(),
        name: LocalizedWords,
        detail: LocalizedWords.optional(),
      })
      .optional()
      .meta({ description: 'What it is about: a symbol, a name and a line.' }),
    stage: z
      .strictObject({
        cast: z.string().meta({
          description:
            'Who stands with the coach: `coach`, `coachAndMe` (the reader), `coachAndSquad` ' +
            '(the squad, in two rows of four past four) or `members` (`members`); more may come.',
          example: 'coachAndMe',
        }),
        members: z.array(z.uuid()).optional().meta({
          description: 'With `members`, these members by id, beside the coach.',
        }),
        move: z.string().optional().meta({
          description: 'The move the coach plays, by the art’s id; left out, its idle.',
        }),
        scene: z.string().optional().meta({
          description: 'The scene behind them, by id; left out, the squad’s scene this week.',
        }),
      })
      .meta({ description: 'The picture on top.' }),
    stars: z.boolean().meta({ description: '`true`: five stars to tap (`stars` answers).' }),
    input: z
      .strictObject({ placeholder: LocalizedWords.optional() })
      .optional()
      .meta({ description: 'A box to type in (`text` answers).' }),
    buttons: z.array(MessageButtonBody).meta({ description: '0 to 3 buttons, left to right.' }),
    thanks: LocalizedWords.optional().meta({
      description: 'What the card says once a button `close`s it.',
    }),
  })
  .openapi('CoachMessageCard');

const AnsweredBody = z
  .strictObject({
    path: WirePath,
    tap: z.string().optional().meta({ description: 'The button the caller tapped.' }),
    stars: z.int().min(1).max(5).optional().meta({ description: 'The stars they gave.' }),
    text: z.string().optional().meta({ description: 'What they typed.' }),
  })
  .openapi('CoachMessageAnswered');

export const CoachMessageBody = z
  .strictObject({
    cards: z.array(MessageCardBody).meta({
      description: 'Every card of the message, the first (path ``) first.',
    }),
    answered: z.array(AnsweredBody).meta({
      description:
        'What the caller did on each card so far; the first answer to each part stands. A card ' +
        'whose tap closed it or turned it shows that on every phone.',
    }),
  })
  .openapi('CoachMessage');

/** A step on the wire; a `next` names the card it turns into, `next` here being its path. */
function wireStep(step: AnyStep, next: string): z.infer<typeof MessageStepBody> {
  if ('open' in step) return { open: step.open };
  if ('feedback' in step) return { feedback: step.feedback };
  if ('close' in step) return { close: true };
  return { next };
}

function wireCard(path: string, card: AnyCard): z.infer<typeof MessageCardBody> {
  const cast = card.stage?.cast ?? 'coachAndMe';
  return {
    path,
    line: card.line,
    ...(card.body === undefined ? {} : { body: card.body }),
    ...(card.about === undefined ? {} : { about: card.about }),
    stage: {
      ...(typeof cast === 'string' ? { cast } : { cast: 'members', members: cast.members }),
      ...(card.stage?.move === undefined ? {} : { move: card.stage.move }),
      ...(card.stage?.scene === undefined ? {} : { scene: card.stage.scene }),
    },
    stars: card.stars === true,
    ...(card.input === undefined ? {} : { input: card.input }),
    buttons: (card.buttons ?? []).map((button) => ({
      id: button.id,
      label: button.label,
      ...(button.icon === undefined ? {} : { icon: button.icon }),
      style: button.style ?? 'outline',
      tap: button.tap.map((step) =>
        wireStep(step, path === '' ? button.id : `${path}.${button.id}`),
      ),
    })),
    ...(card.thanks === undefined ? {} : { thanks: card.thanks }),
  };
}

/** A message and what the caller answered, as the coach page reads it. */
export function wireMessage(
  value: MessageValue,
  answered: ReadonlyMap<string, Answered>,
): z.infer<typeof CoachMessageBody> {
  return {
    cards: [...cardsOf(value.card)].map(([path, card]) => wireCard(path, card)),
    answered: [...answered].map(([path, each]) => ({ path, ...each })),
  };
}

const AnswerBody = z
  .strictObject({
    version: bodyVersion(1),
    path: CardPath.meta({ description: 'The card answered, by its path.', example: '' }),
    tap: ButtonId.optional().meta({ description: 'The button tapped.', example: 'yes' }),
    stars: z.int().min(1).max(5).optional().meta({ description: 'The stars given.' }),
    text: z
      .string()
      .max(TEXT_LIMIT * 2)
      .optional()
      .meta({
        description: `What was typed; kept trimmed, up to ${String(TEXT_LIMIT)} characters.`,
      }),
  })
  .refine(
    (body) => [body.tap, body.stars, body.text].filter((part) => part !== undefined).length === 1,
    { message: 'One of `tap`, `stars` or `text`' },
  )
  .openapi('CoachMessageAnswer');

const AnsweredReply = z
  .strictObject({
    version: bodyVersion(1),
    id: z.string().meta({ description: 'The message.' }),
    answered: z.array(AnsweredBody),
  })
  .openapi('CoachMessageAnswers');

function partOf(body: z.infer<typeof AnswerBody>): AnswerPart {
  if (body.tap !== undefined) return { part: 'tap', button: body.tap };
  if (body.stars !== undefined) return { part: 'stars', stars: body.stars };
  return { part: 'text', text: body.text ?? '' };
}

/** `PUT /squads/{squadId}/coach/messages/{messageId}/answer`: one part of an answer to a card. */
export function coachMessageAnswers(deps: {
  readonly verifyToken: VerifyToken;
  readonly squads: Squads;
  readonly coachMessages: Pick<CoachMessages, 'answer'>;
}) {
  const answer = createRoute({
    method: 'put',
    path: '/squads/{squadId}/coach/messages/{messageId}/answer',
    operationId: 'answerCoachMessage',
    summary: 'Keep what the caller did on one card of a coach message',
    description:
      'One part of the caller’s answer on one card of a coach message they got (a `message` ' +
      'card on the coach page): the button they tapped, the stars they gave or what they typed. ' +
      'Each part once a card; the first stands, and sending it again gets the answers back. A ' +
      'follow-up card takes answers once the button that turns into it was tapped. Sending ' +
      '意见反馈 is the app’s own `POST /feedback`.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({ squadId: SquadId, messageId: MessageId }),
      body: { content: { 'application/json': { schema: AnswerBody } }, required: true },
    },
    responses: {
      200: {
        description: 'Everything the caller answered on the message so far',
        content: { 'application/json': { schema: AnsweredReply } },
      },
      400: problem(
        'Not a valid squad or message id, or not an answer that card takes ' +
          '(`COACH_MESSAGE_ANSWER_INVALID`)',
      ),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      404: problem('Not a message the caller got in this squad (`COACH_MESSAGE_NOT_FOUND`)'),
      ...jsonBodyFailures,
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>().openapi(answer, async (c) => {
    const { squadId, messageId } = c.req.valid('param');
    const body = c.req.valid('json');
    const member = c.var.caller.userId;
    // Throws `SquadNotJoinedError` for anyone not in the squad.
    await deps.squads.find({ squad: squadId, viewer: MemberId.parse(member) });
    const answered = await deps.coachMessages.answer({
      member: MessageMember.parse(member),
      squad: MessageSquad.parse(squadId),
      message: messageId,
      path: body.path,
      part: partOf(body),
    });
    return c.json(
      {
        version: 1 as const,
        id: messageId,
        answered: [...answered].map(([path, each]) => ({ path, ...each })),
      },
      200,
    );
  });
}
