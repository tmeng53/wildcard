import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  MAX_CHECK_INS,
  REPLY_LIMIT,
  SquadId as CoachSquadId,
  type CoachActivity,
  type CoachReply,
} from '@wildcard/coach';
import { MemberId, SquadId, type Squads } from '@wildcard/squads';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const CoachSpeakerBody = z
  .strictObject({
    id: z.string().meta({ description: 'The coach’s id. Never changes.', example: 'xiaohun' }),
    name: z.string().meta({ description: 'Its name, shown with the 教练 tag.', example: '毛头' }),
    look: z.string().meta({ description: 'The character the app draws, by the art’s id.' }),
  })
  .openapi('CoachSpeaker');

const CoachNoteBody = z
  .strictObject({
    day: z.iso.date().meta({ description: 'The day (New York) the line is for.' }),
    text: z.string().meta({ description: 'The 战术板 line.', example: '今天谁先动，谁就是队长' }),
    coach: CoachSpeakerBody,
    at: z.iso.datetime(),
  })
  .openapi('CoachNote');

const CoachReplyBody = z
  .strictObject({
    checkInId: z.uuid(),
    coach: CoachSpeakerBody.meta({
      description: 'The coach who replied, even if the squad has fired it since.',
    }),
    text: z
      .string()
      .max(REPLY_LIMIT)
      .nullable()
      .meta({
        description:
          'Its line, shown first among the post’s comments with the 教练 tag, which members may ' +
          'reply to (a comment with `replyToCoach`), or null when it only reacted.',
      }),
    emoji: z
      .string()
      .nullable()
      .meta({
        description:
          'Its reaction, shown first among the post’s reactions with the 教练 tag, or null when ' +
          'it only spoke. Not counted in the post’s reactions.',
      }),
    at: z.iso.datetime(),
  })
  .openapi('CoachReply');

const CoachAnswerBody = z
  .strictObject({
    checkInId: z.uuid(),
    commentId: z.uuid().meta({
      description: 'The member’s reply to the coach (`replyToCoach`) this answers.',
    }),
    coach: CoachSpeakerBody.meta({
      description: 'The coach who answered, even if the squad has fired it since.',
    }),
    text: z
      .string()
      .max(REPLY_LIMIT)
      .meta({
        description:
          'Its answer, shown among the post’s comments right after the reply it answers, as a ' +
          'reply to that reply’s writer (毛头 回复 小美：…), with the 教练 tag.',
      }),
    at: z.iso.datetime(),
  })
  .openapi('CoachAnswer');

const CoachActivityBody = z
  .strictObject({
    version: bodyVersion(1),
    note: CoachNoteBody.nullable().meta({
      description:
        'The squad’s newest 战术板 line (the app shows it while its day is today), or null.',
    }),
    replies: z.array(CoachReplyBody).meta({
      description: 'The coach’s replies to the check-ins asked about; one with none is left out.',
    }),
    answers: z.array(CoachAnswerBody).meta({
      description:
        'The coach’s answers to members’ replies to it under the check-ins asked about, oldest ' +
        'first.',
    }),
  })
  .openapi('CoachActivity');

const checkInIds = z
  .string()
  .optional()
  .transform((value, context) => {
    const ids = (value ?? '').split(',').filter((id) => id !== '');
    if (ids.length > MAX_CHECK_INS) {
      context.addIssue({ code: 'custom', message: `At most ${String(MAX_CHECK_INS)} check-ins.` });
      return z.NEVER;
    }
    for (const id of ids) {
      if (!z.uuid().safeParse(id).success) {
        context.addIssue({ code: 'custom', message: `${id} isn’t a check-in id.` });
        return z.NEVER;
      }
    }
    return ids;
  })
  .openapi({
    type: 'string',
    description: `Check-in ids, comma-separated, up to ${String(MAX_CHECK_INS)}: the posts on screen.`,
    example: '0a5c1f2e-3b4d-4e6f-8a9b-1c2d3e4f5a6b,1b6d2f3e-4c5d-4f6a-9b8c-2d3e4f5a6b7c',
  });

function speaker(coach: CoachReply['coach']) {
  return { id: coach.id, name: coach.name, look: coach.look };
}

/**
 * `GET /squads/{squadId}/coach/activity`: what the squad's coach said, for 今天's sideline coach
 * and 动态 (its 战术板 line, and its replies and reactions to posts, shown with the 教练 tag).
 * Apart from the feed and comments, so builds that don't know the coach read those unchanged.
 */
export function coachActivity(deps: {
  readonly verifyToken: VerifyToken;
  readonly squads: Squads;
  readonly coachActivity: CoachActivity;
}) {
  const read = createRoute({
    method: 'get',
    path: '/squads/{squadId}/coach/activity',
    operationId: 'getSquadCoachActivity',
    summary: 'What the squad’s coach said (战术板, replies and reactions)',
    description:
      'The newest 战术板 line, and the coach’s reply (a line, an emoji or both) to each of the ' +
      'check-ins asked about that has one, and its answers to members’ replies to it there. ' +
      'Only for the squad’s members. They stay after the squad fires its coach.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({ squadId: SquadId }),
      query: z.strictObject({ checkIns: checkInIds }),
    },
    responses: {
      200: {
        description: 'What the coach said',
        content: { 'application/json': { schema: CoachActivityBody } },
      },
      400: problem('Not a valid squad id, or not valid check-in ids, or more than 100'),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>().openapi(read, async (c) => {
    const { squadId } = c.req.valid('param');
    // Throws `SquadNotJoinedError` for anyone not in the squad.
    await deps.squads.find({ squad: squadId, viewer: MemberId.parse(c.var.caller.userId) });
    const { note, replies, answers } = await deps.coachActivity.squad({
      squad: CoachSquadId.parse(squadId),
      checkIns: c.req.valid('query').checkIns,
    });
    return c.json(
      {
        version: 1 as const,
        note:
          note === undefined
            ? null
            : {
                day: note.day,
                text: note.text,
                coach: speaker(note.coach),
                at: note.at.toISOString(),
              },
        replies: replies.map((reply) => ({
          checkInId: reply.checkIn,
          coach: speaker(reply.coach),
          text: reply.text ?? null,
          emoji: reply.emoji ?? null,
          at: reply.at.toISOString(),
        })),
        answers: answers.map((answer) => ({
          checkInId: answer.checkIn,
          commentId: answer.comment,
          coach: speaker(answer.coach),
          text: answer.text,
          at: answer.at.toISOString(),
        })),
      },
      200,
    );
  });
}
