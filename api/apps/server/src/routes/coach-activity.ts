import { NEW_YORK, TimeZone } from '@wildcard/time-zones';
import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  MAX_CHECK_INS,
  REPLY_LIMIT,
  SquadId as CoachSquadId,
  type CoachActivity,
  type CoachReply,
} from '@wildcard/coach';
import { MemberId as PushMember, type Push } from '@wildcard/push';
import { MemberId, SquadId, type Squads } from '@wildcard/squads';

import { bodyVersion } from '../body-version.js';
import type { CoachNames } from '../flows/coach-names.js';
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
    day: z.iso.date().meta({
      description: 'The day the line is for, on the squad’s clock (`timeZone`).',
    }),
    text: z.string().meta({ description: 'The 战术板 line.', example: '今天谁先动，谁就是队长' }),
    coach: CoachSpeakerBody,
    at: z.iso.datetime(),
    timeZone: TimeZone.meta({
      description:
        'The squad’s time zone (小队时区) now, whose day `day` is: the app shows the line while ' +
        'it is still that day there.',
      example: 'Asia/Taipei',
    }),
  })
  .openapi('CoachNote');

const CoachMemberNoteBody = z
  .strictObject({
    id: z.int().positive().meta({
      description: 'The note’s id, which putting it away (收下) and `coachNote` notices name.',
    }),
    day: z.iso
      .date()
      .meta({ description: 'The day, on the squad’s clock, the note was written for.' }),
    text: z.string().meta({ description: 'The note’s words.', example: '昨天那组深蹲我看见了' }),
    coach: CoachSpeakerBody,
    at: z.iso.datetime().meta({ description: 'When it was written.' }),
  })
  .openapi('CoachMemberNote');

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
    memberNote: CoachMemberNoteBody.optional().meta({
      description:
        'The caller’s own newest morning note (便条) from the squad’s coach, for 今天 to show when ' +
        'the caller opens it; only the caller sees it. Left out when there is none ' +
        'from the last day and a half, or while the caller’s `coach` push switch is off.',
    }),
  })
  .openapi('CoachActivity');

const CoachNotePutAway = z
  .strictObject({ version: bodyVersion(1), noteId: z.int().positive() })
  .openapi('CoachNotePutAway');

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

/** Who said it, named as the squad calls the coach. */
function speakerIn(named: (coach: string) => string | undefined) {
  return (coach: CoachReply['coach']) => ({
    id: coach.id,
    name: named(coach.id) ?? coach.name,
    look: coach.look,
  });
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
  /** The reader's `coach` switch: switched off, no morning note shows (Tracy, 2026-11-07). */
  readonly push: Pick<Push, 'settingsOf'>;
  readonly coachNames: CoachNames;
}) {
  const read = createRoute({
    method: 'get',
    path: '/squads/{squadId}/coach/activity',
    operationId: 'getSquadCoachActivity',
    summary: 'What the squad’s coach said (战术板, replies and reactions)',
    description:
      'The newest 战术板 line, and the coach’s reply (a line, an emoji or both) to each of the ' +
      'check-ins asked about that has one, its answers to members’ replies to it there, and the ' +
      'caller’s own morning note. ' +
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

  const putAway = createRoute({
    method: 'put',
    path: '/squads/{squadId}/coach/notes/{noteId}/put-away',
    operationId: 'putAwayCoachMemberNote',
    summary: 'Put the caller’s morning note away (收下)',
    description:
      'The caller read their morning note (便条) on 今天 and put it away, so it no longer comes ' +
      'back as `memberNote` on any of their phones; 通知 keeps it. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({
        squadId: SquadId,
        noteId: z.coerce.number().int().positive().openapi({ type: 'integer' }),
      }),
    },
    responses: {
      200: {
        description: 'Put away',
        content: { 'application/json': { schema: CoachNotePutAway } },
      },
      400: problem('Not a valid squad or note id'),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      404: problem('Not one of the caller’s notes in this squad (`COACH_NOTE_NOT_FOUND`)'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(putAway, async (c) => {
      const { squadId, noteId } = c.req.valid('param');
      const member = c.var.caller.userId;
      await deps.squads.find({ squad: squadId, viewer: MemberId.parse(member) });
      await deps.coachActivity.putAway({
        squad: CoachSquadId.parse(squadId),
        member,
        note: noteId,
      });
      return c.json({ version: 1 as const, noteId }, 200);
    })
    .openapi(read, async (c) => {
      const { squadId } = c.req.valid('param');
      // Throws `SquadNotJoinedError` for anyone not in the squad.
      await deps.squads.find({ squad: squadId, viewer: MemberId.parse(c.var.caller.userId) });
      const zone = (await deps.squads.timeZonesAt([squadId], new Date())).get(squadId) ?? NEW_YORK;
      const {
        note,
        replies,
        answers,
        memberNote: written,
      } = await deps.coachActivity.squad({
        squad: CoachSquadId.parse(squadId),
        checkIns: c.req.valid('query').checkIns,
        reader: c.var.caller.userId,
      });
      // A switch that can't be read counts as off, so the rest of the activity still shows.
      const memberNote =
        written !== undefined &&
        (await deps.push
          .settingsOf(PushMember.parse(c.var.caller.userId))
          .then((settings) => settings.coach)
          .catch(() => false))
          ? written
          : undefined;
      const coaches = [
        ...(note === undefined ? [] : [note.coach.id]),
        ...replies.map((reply) => reply.coach.id),
        ...answers.map((answer) => answer.coach.id),
        ...(memberNote === undefined ? [] : [memberNote.coach.id]),
      ];
      const named = await deps.coachNames(coaches.map((coach) => ({ coach, squad: squadId })));
      const speaker = speakerIn((coach) => named(coach, squadId));
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
                  timeZone: zone,
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
          ...(memberNote === undefined
            ? {}
            : {
                memberNote: {
                  id: memberNote.id,
                  day: memberNote.day,
                  text: memberNote.text,
                  coach: speaker(memberNote.coach),
                  at: memberNote.at.toISOString(),
                },
              }),
        },
        200,
      );
    });
}
