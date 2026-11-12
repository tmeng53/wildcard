import { TimeZone, wallClockAt } from '@wildcard/time-zones';
import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  LETTER_LIMIT,
  CHALLENGE_AMOUNT_MAX,
  CHALLENGE_LINE_LIMIT,
  CHALLENGE_TITLE_LIMIT,
  CHALLENGE_UNIT_LIMIT,
  ChallengeAnswer,
  ChallengeDoneBy,
  DECLINE_REASON_LIMIT,
  DeclineReason,
  MAX_CHECK_INS,
  REPLY_LIMIT,
  SquadId as CoachSquadId,
  type Challenge,
  type ChallengeCompletion,
  type CoachActivity,
  type CoachLetter,
  type CoachReply,
} from '@wildcard/coach';
import { MemberId as PushMember, type Push } from '@wildcard/push';
import { MemberId, SquadId, type Squads } from '@wildcard/squads';

import { bodyVersion } from '../body-version.js';
import type { CoachNames } from '../flows/coach-names.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

export const CoachSpeakerBody = z
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

const ChallengeAnswerBody = ChallengeAnswer.meta({
  description: '`accepted` for 接受挑战, `declined` for 算了.',
});

const ChallengeDoneByBody = ChallengeDoneBy.meta({
  description:
    '`member` for the member’s own 我完成了, `coach` when the coach saw it in their check-ins.',
});

export const CoachChallengeBody = z
  .strictObject({
    title: z.string().max(CHALLENGE_TITLE_LIMIT).meta({
      description: 'What to do, in a few words.',
      example: '喝水',
    }),
    amount: z.int().min(1).max(CHALLENGE_AMOUNT_MAX).optional().meta({
      description: 'How much, when it has a number; always with `unit`.',
      example: 8,
    }),
    unit: z.string().max(CHALLENGE_UNIT_LIMIT).optional().meta({
      description: 'The amount’s unit, the coach’s own word.',
      example: '杯',
    }),
    line: z.string().max(CHALLENGE_LINE_LIMIT).optional().meta({
      description:
        'The coach talking to the member under the title, about why; left out on older notes.',
      example: '泳池泡久了也会渴，别等口干。',
    }),
    answer: ChallengeAnswerBody.optional().meta({
      description: 'What the member said to it; left out until they answer. The first stands.',
    }),
    reason: z.string().max(DECLINE_REASON_LIMIT).optional().meta({
      description: 'Why the member let it go, when they said; only the member sees it.',
    }),
    completedAt: z.iso.datetime().optional().meta({
      description: 'When it was marked done (已完成); left out until it is. The first stands.',
    }),
    completedBy: ChallengeDoneByBody.optional().meta({
      description: 'Who marked it done, with `completedAt`.',
    }),
  })
  .openapi('CoachChallenge');

/** A challenge as the app reads it, with what the member said to it and whether it is done. */
export function wireChallenge({
  challenge,
  answer,
  reason,
  completion,
}: {
  readonly challenge: Challenge;
  readonly answer: ChallengeAnswer | undefined;
  readonly reason: string | undefined;
  readonly completion: ChallengeCompletion | undefined;
}): z.infer<typeof CoachChallengeBody> {
  return {
    ...challenge,
    ...(answer === undefined ? {} : { answer }),
    ...(reason === undefined ? {} : { reason }),
    ...(completion === undefined
      ? {}
      : { completedAt: completion.at.toISOString(), completedBy: completion.by }),
  };
}

const CoachDayChallengeBody = z
  .strictObject({
    version: bodyVersion(1),
    today: z
      .strictObject({
        noteId: z.int().positive().meta({
          description: 'The morning note that set it, which answering and completing it name.',
        }),
        day: z.iso.date().meta({ description: 'Its day, on the squad’s clock.' }),
        challenge: CoachChallengeBody,
        // The coach who set it, named as the squad calls it; still that coach after the squad
        // changes coach. Without a description of its own, which would wrap it in an `allOf`.
        coach: CoachSpeakerBody,
      })
      .nullable()
      .meta({
        description:
          'The caller’s challenge today, once their morning note reached them; `null` when ' +
          'there is none, or while their `coach` switch is off.',
      }),
  })
  .openapi('CoachDayChallenge');

const ChallengeCompleted = z
  .strictObject({
    version: bodyVersion(1),
    noteId: z.int().positive(),
    completedAt: z.iso.datetime(),
    completedBy: ChallengeDoneByBody,
  })
  .openapi('CoachChallengeCompleted');

const CoachMemberNoteBody = z
  .strictObject({
    id: z.int().positive().meta({
      description:
        'The note’s id, which its card on the coach’s page and `coachNote` notices name.',
    }),
    day: z.iso
      .date()
      .meta({ description: 'The day, on the squad’s clock, the note was written for.' }),
    text: z.string().meta({ description: 'The note’s words.', example: '昨天那组深蹲我看见了' }),
    // The day's challenge (今日挑战) the note sets, if any; only the member sees it. Left without
    // a description of its own, which would wrap it in an `allOf` installed builds read as new.
    challenge: CoachChallengeBody.optional(),
    coach: CoachSpeakerBody,
    at: z.iso.datetime().meta({ description: 'When it was written.' }),
  })
  .openapi('CoachMemberNote');

export const CoachLetterBody = z
  .strictObject({
    id: z
      .int()
      .positive()
      .meta({ description: 'The letter’s id, which `coachLetter` notices name.' }),
    from: CoachSpeakerBody.meta({ description: 'The coach who wrote it as it left: its 落款.' }),
    to: CoachSpeakerBody.meta({ description: 'The coach who took over: its 称呼.' }),
    day: z.iso.date().meta({ description: 'The day it is dated, on the squad’s clock.' }),
    text: z
      .string()
      .max(LETTER_LIMIT * 2)
      .meta({
        description: 'Its body, without the 称呼 or 落款; lines apart by `\\n`.',
        example: '这队交给你了，我先撤。',
      }),
    at: z.iso.datetime().meta({ description: 'When it was written.' }),
  })
  .openapi('CoachLetter');

/** A letter as the app reads it, its coaches named by `speaker`. */
export function wireLetter(
  letter: CoachLetter,
  speaker: ReturnType<typeof speakerIn>,
): z.infer<typeof CoachLetterBody> {
  return {
    id: letter.id,
    from: speaker(letter.from),
    to: speaker(letter.to),
    day: letter.day,
    text: letter.text,
    at: letter.at.toISOString(),
  };
}
const ChallengeAnswered = z
  .strictObject({
    version: bodyVersion(1),
    noteId: z.int().positive(),
    answer: ChallengeAnswerBody,
    reason: z.string().max(DECLINE_REASON_LIMIT).optional().meta({
      description: 'Why they let it go, when they said; the first answer’s.',
    }),
  })
  .openapi('CoachChallengeAnswered');

const CoachReplyBody = z
  .strictObject({
    checkInId: z.uuid(),
    coach: CoachSpeakerBody.meta({
      description: 'The coach who replied, even if the squad has fired it since.',
    }),
    text: z
      .string()
      .max(REPLY_LIMIT * 2)
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
    mentions: z
      .array(z.uuid())
      .optional()
      .meta({
        description:
          'Whom its line @s, in the order written, when it @s anyone: each 「@昵称」 at its start, ' +
          'which the app shows as a tag that opens that member’s card. One whose account is ' +
          'deleted is gone.',
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
      .max(REPLY_LIMIT * 2)
      .meta({
        description:
          'Its answer, shown among the post’s comments right after the reply it answers, as a ' +
          'reply to that reply’s writer (毛头 回复 小美：…), with the 教练 tag.',
      }),
    mentions: z
      .array(z.uuid())
      .optional()
      .meta({
        description:
          'Whom it @s, in the order written, when it @s anyone: each 「@昵称」 at its start, ' +
          'which the app shows as a tag that opens that member’s card. One whose account is ' +
          'deleted is gone.',
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
    letter: CoachLetterBody.optional().meta({
      description:
        'The letter the squad’s coach now was left by the coach before it when the squad changed ' +
        'coach (换教练), for 今天 to open once on each phone and the coach’s 简历 to keep. Left ' +
        'out when it wasn’t left one.',
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

/** Who said it, named as the squad calls the coach. */
export function speakerIn(named: (coach: string) => string | undefined) {
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
      'caller’s own morning note, and the letter the coach now was left when it took over. ' +
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

  const answerChallenge = createRoute({
    method: 'put',
    path: '/squads/{squadId}/coach/notes/{noteId}/challenge',
    operationId: 'answerCoachChallenge',
    summary: 'Accept or decline the challenge on the caller’s morning note',
    description:
      '接受挑战 or 算了 on the day’s challenge the caller’s morning note sets, with why they let it ' +
      'go if they say (their coach remembers it; squadmates never see it). The first answer ' +
      'stands; answering again gets it back. The coach sees it when the member next checks in.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({
        squadId: SquadId,
        noteId: z.coerce.number().int().positive().openapi({ type: 'integer' }),
      }),
      body: {
        content: {
          'application/json': {
            schema: z
              .strictObject({
                version: bodyVersion(1),
                answer: ChallengeAnswerBody,
                reason: DeclineReason.optional(),
              })
              .refine(({ answer, reason }) => reason === undefined || answer === 'declined', {
                message: 'A reason comes only with `declined`',
                path: ['reason'],
              })
              .openapi('CoachChallengeAnswer'),
          },
        },
        required: true,
      },
    },
    responses: {
      200: {
        description: 'The answer that stands',
        content: { 'application/json': { schema: ChallengeAnswered } },
      },
      400: problem(
        'Not a valid squad or note id, not an answer, or a note with no challenge ' +
          '(`COACH_NOTE_NO_CHALLENGE`)',
      ),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      404: problem('Not one of the caller’s notes in this squad (`COACH_NOTE_NOT_FOUND`)'),
      ...jsonBodyFailures,
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  const todaysChallenge = createRoute({
    method: 'get',
    path: '/squads/{squadId}/coach/challenge',
    operationId: 'getCoachChallenge',
    summary: 'The caller’s challenge today (今日挑战)',
    description:
      'The day’s challenge the squad’s coach set the caller on today’s morning note (today on ' +
      'the squad’s clock), once the note reached them: what it is, what they said to it, and ' +
      'whether it is done, by them (我完成了) or by the coach from their check-ins. Only the ' +
      'caller sees it.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId }) },
    responses: {
      200: {
        description: 'Today’s challenge, or `null`',
        content: { 'application/json': { schema: CoachDayChallengeBody } },
      },
      400: problem('Not a valid squad id'),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  const completeChallenge = createRoute({
    method: 'put',
    path: '/squads/{squadId}/coach/notes/{noteId}/challenge/completion',
    operationId: 'completeCoachChallenge',
    summary: 'Mark the challenge on the caller’s morning note done (我完成了)',
    description:
      'The caller did the day’s challenge their morning note sets. Only on its own day, on the ' +
      'squad’s clock, and not once they let it go (算了). The first completion stands, theirs or ' +
      'the coach’s, and is what comes back, so repeating it is safe.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({
        squadId: SquadId,
        noteId: z.coerce.number().int().positive().openapi({ type: 'integer' }),
      }),
      body: {
        content: {
          'application/json': {
            schema: z.strictObject({ version: bodyVersion(1) }).openapi('CoachChallengeCompletion'),
          },
        },
        required: true,
      },
    },
    responses: {
      200: {
        description: 'The completion that stands',
        content: { 'application/json': { schema: ChallengeCompleted } },
      },
      400: problem(
        'Not a valid squad or note id, a note with no challenge (`COACH_NOTE_NO_CHALLENGE`), ' +
          'one the caller let go (`COACH_CHALLENGE_DECLINED`), or another day’s ' +
          '(`COACH_CHALLENGE_DAY_OVER`)',
      ),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      404: problem('Not one of the caller’s notes in this squad (`COACH_NOTE_NOT_FOUND`)'),
      ...jsonBodyFailures,
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  /** Today on the squad's clock, the day a challenge counts on. */
  const todayOf = async (squad: z.infer<typeof SquadId>) => {
    const now = new Date();
    return wallClockAt(now, (await deps.squads.timeZonesAt([squad], now))(squad)).day;
  };

  return new OpenAPIHono<SignedIn>()
    .openapi(todaysChallenge, async (c) => {
      const { squadId } = c.req.valid('param');
      const member = c.var.caller.userId;
      await deps.squads.find({ squad: squadId, viewer: MemberId.parse(member) });
      // Like the morning note, it shows only while their `coach` switch is on; one that can't be
      // read counts as off.
      const on = await deps.push
        .settingsOf(PushMember.parse(member))
        .then((settings) => settings.coach)
        .catch(() => false);
      const today = on
        ? await deps.coachActivity.challenge({
            squad: CoachSquadId.parse(squadId),
            member,
            today: await todayOf(squadId),
          })
        : undefined;
      const named =
        today === undefined
          ? undefined
          : await deps.coachNames([{ coach: today.coach.id, squad: squadId }]);
      return c.json(
        {
          version: 1 as const,
          today:
            today === undefined || named === undefined
              ? null
              : {
                  noteId: today.note,
                  day: today.day,
                  challenge: wireChallenge(today),
                  coach: speakerIn((coach) => named(coach, squadId))(today.coach),
                },
        },
        200,
      );
    })
    .openapi(completeChallenge, async (c) => {
      const { squadId, noteId } = c.req.valid('param');
      const member = c.var.caller.userId;
      await deps.squads.find({ squad: squadId, viewer: MemberId.parse(member) });
      const done = await deps.coachActivity.completeChallenge({
        squad: CoachSquadId.parse(squadId),
        member,
        note: noteId,
        today: await todayOf(squadId),
      });
      return c.json(
        {
          version: 1 as const,
          noteId,
          completedAt: done.at.toISOString(),
          completedBy: done.by,
        },
        200,
      );
    })
    .openapi(answerChallenge, async (c) => {
      const { squadId, noteId } = c.req.valid('param');
      const member = c.var.caller.userId;
      await deps.squads.find({ squad: squadId, viewer: MemberId.parse(member) });
      const { answer, reason } = c.req.valid('json');
      const kept = await deps.coachActivity.answerChallenge({
        squad: CoachSquadId.parse(squadId),
        member,
        note: noteId,
        answer,
        ...(reason === undefined ? {} : { reason }),
      });
      return c.json({ version: 1 as const, noteId, ...kept }, 200);
    })
    .openapi(read, async (c) => {
      const { squadId } = c.req.valid('param');
      // Throws `SquadNotJoinedError` for anyone not in the squad.
      await deps.squads.find({ squad: squadId, viewer: MemberId.parse(c.var.caller.userId) });
      const zone = (await deps.squads.timeZonesAt([squadId], new Date()))(squadId);
      const {
        note,
        replies,
        answers,
        memberNote: written,
        letter,
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
        ...(letter === undefined ? [] : [letter.from.id, letter.to.id]),
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
            ...(reply.mentions.length === 0 ? {} : { mentions: [...reply.mentions] }),
            at: reply.at.toISOString(),
          })),
          answers: answers.map((answer) => ({
            checkInId: answer.checkIn,
            commentId: answer.comment,
            coach: speaker(answer.coach),
            text: answer.text,
            ...(answer.mentions.length === 0 ? {} : { mentions: [...answer.mentions] }),
            at: answer.at.toISOString(),
          })),
          ...(memberNote === undefined
            ? {}
            : {
                memberNote: {
                  id: memberNote.id,
                  day: memberNote.day,
                  text: memberNote.text,
                  ...(memberNote.challenge === undefined
                    ? {}
                    : {
                        challenge: {
                          ...memberNote.challenge,
                          ...(memberNote.challengeAnswer === undefined
                            ? {}
                            : { answer: memberNote.challengeAnswer }),
                        },
                      }),
                  coach: speaker(memberNote.coach),
                  at: memberNote.at.toISOString(),
                },
              }),
          ...(letter === undefined ? {} : { letter: wireLetter(letter, speaker) }),
        },
        200,
      );
    });
}
