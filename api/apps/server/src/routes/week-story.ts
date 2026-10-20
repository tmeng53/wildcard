import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { LocalDay, ReactionKind, SquadId, WeekStart } from '@wildcard/check-ins';
import {
  AWARD_MOVES,
  CheckInKind,
  SPEECH_MAX,
  TITLE_MAX,
  TITLES_MAX,
  SquadId as AwardsSquad,
  WeekStart as AwardsWeek,
  type TopCheckIn,
} from '@wildcard/weekly-awards';

import { bodyVersion } from '../body-version.js';
import {
  nudgeOrganisers,
  squadStory,
  type WeeklyAwardsDependencies,
} from '../flows/weekly-awards.js';
import { PhotoPath, type PhotoStorage, type VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { languageOf, REACTION_COPY } from './week-summary-copy.js';

/** How long a photo's view URL works. The app reads the story again for fresh ones. */
const PHOTO_VIEW_SECONDS = 60 * 60;

const DAY = 86_400_000;

const move = (description: string) =>
  z
    .string()
    .min(1)
    .meta({
      description:
        `${description} Today one of ${Object.keys(AWARD_MOVES)
          .map((each) => `\`${each}\``)
          .join(', ')} (\`cheer\` is the persona’s own cheer). New moves come without an app ` +
        'release: play `cheer` for one the app doesn’t know.',
      example: 'pump',
    });

const Title = z
  .strictObject({
    title: z
      .string()
      .min(1)
      .meta({
        description: `The title (头衔), at most ${String(TITLE_MAX)} characters.`,
        example: '雨中狠人',
      }),
    speech: z
      .string()
      .min(1)
      .meta({
        description: `Its award line (颁奖词), at most ${String(SPEECH_MAX)} characters, citing something real from the week.`,
        example: '周三下着雨还去跑了 5 公里',
      }),
    move: move('The move the character plays collecting it.'),
  })
  .openapi('StoryTitle');

const Hottest = z
  .strictObject({
    checkIn: z.uuid(),
    day: LocalDay,
    kind: CheckInKind,
    sport: z.string().optional().meta({
      description: 'For a 练了: the listed sport’s key, or the name of the member’s own.',
    }),
    caption: z.string().optional(),
    text: z.string().optional().meta({ description: 'For a 请假条: its text.' }),
    photos: z
      .array(
        z
          .strictObject({
            path: z.string(),
            url: z.url().meta({ description: '`GET` the photo here. It works for an hour.' }),
          })
          .openapi('StoryPhoto'),
      )
      .meta({ description: 'Up to 3 photos, the cover first; empty when there are none.' }),
    reactions: z
      .array(
        z.strictObject({
          kind: z.string().min(1).meta({
            description: 'Today `cheer`, `highlight` or `lol`; show any kind from its label.',
          }),
          label: z.string().min(1).meta({ description: 'Its name, in the language asked for.' }),
          count: z.int().min(1),
        }),
      )
      .meta({ description: 'Teammates’ reactions on it by kind, as they stood at the awards.' }),
  })
  .openapi('StoryHottest');

export const WeekStoryBody = z
  .strictObject({
    version: bodyVersion(1),
    language: z
      .string()
      .min(1)
      .meta({
        description:
          'The language of the reaction labels: today `zh-Hans` or `en`. The AI writes its lines ' +
          'in Chinese.',
      }),
    status: z.enum(['ready', 'pending']).meta({
      description:
        '`ready` once the week’s titles are written. `pending` when they are due but not ' +
        'written yet (the AI failed, or hasn’t reached the squad): only the titles page waits, ' +
        'showing that the organisers are out of funds with a button that nudges them ' +
        '(`POST …/story/nudge`); every other page shows as usual. Read again later.',
    }),
    squad: z.strictObject({ id: z.uuid(), name: z.string() }),
    week: z.strictObject({ from: WeekStart, to: LocalDay }),
    titles: z
      .array(
        z.strictObject({
          member: z.uuid(),
          titles: z.array(Title).min(1).max(TITLES_MAX).meta({ description: 'The best first.' }),
        }),
      )
      .optional()
      .meta({
        description:
          'Once `ready`: every member still in the squad who checked in before the awards, in ' +
          'the order they joined, with 1 to 3 titles. Empty when nobody checked in; missing ' +
          'while `pending`. The weekly poster’s stickers read these too.',
      }),
    hottest: Hottest.optional().meta({
      description:
        'The signed-in member’s check-in with the most reactions at the awards, the latest on a ' +
        'tie; while `pending`, as it stands now. No AI writes it. Missing when none of theirs ' +
        'had any.',
    }),
  })
  .openapi('WeekStory');

/** `GET /squads/{squadId}/weeks/{weekStart}/story`: a squad's Sunday 战报 story. */
export function weekStory(
  deps: Pick<
    WeeklyAwardsDependencies,
    'checkIns' | 'squads' | 'awards' | 'push' | 'admins' | 'clock' | 'log'
  > & {
    readonly verifyToken: VerifyToken;
    readonly photos: PhotoStorage;
  },
) {
  const params = z.strictObject({
    squadId: SquadId,
    weekStart: WeekStart.meta({ description: 'The week’s Monday.', example: '2026-10-19' }),
  });
  const route = createRoute({
    method: 'get',
    path: '/squads/{squadId}/weeks/{weekStart}/story',
    operationId: 'getSquadWeekStory',
    summary: 'A squad’s Sunday 战报 story: the week’s AI awards (本周颁奖)',
    description:
      'Written once for the whole squad on Sunday at 8pm Eastern, by an AI from the week’s ' +
      'check-ins made before then: 1 to 3 titles for each member who checked in, nothing for ' +
      'anyone who didn’t. Check-ins made later still count for the week, only not for its ' +
      'awards. Only for members of the squad. Reaction labels come in the language of the ' +
      'request’s `Accept-Language`, as the week summary’s do.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      200: {
        description: 'The story, or `pending` while it is being written',
        content: { 'application/json': { schema: WeekStoryBody } },
      },
      400: problem('Not a Monday'),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The member isn’t in this squad'),
      404: problem('Before the week’s awards on Sunday at 8pm Eastern (`WEEK_STORY_NOT_READY`)'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  const nudge = createRoute({
    method: 'post',
    path: '/squads/{squadId}/weeks/{weekStart}/story/nudge',
    operationId: 'nudgeSquadWeekStory',
    summary: 'Nudges the organisers about a story whose titles haven’t come (催一下主办方)',
    description:
      'For the button on a `pending` story’s titles page. The first nudge since the last failed ' +
      'try tells the admins, with the failed tries and why; other nudges, and nudges once the ' +
      'titles are written, change nothing. Answers 204 either way.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      204: { description: 'Nudged, or nothing to nudge about' },
      400: problem('Not a Monday'),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The member isn’t in this squad'),
      404: problem('Before the week’s awards on Sunday at 8pm Eastern (`WEEK_STORY_NOT_READY`)'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(nudge, async (c) => {
      const { squadId, weekStart } = c.req.valid('param');
      await nudgeOrganisers(deps, {
        viewer: c.var.caller.userId,
        squad: AwardsSquad.parse(squadId),
        weekStart: AwardsWeek.parse(weekStart),
      });
      return c.body(null, 204);
    })
    .openapi(route, async (c) => {
      const { squadId, weekStart } = c.req.valid('param');
      const language = languageOf(c.req.header('accept-language'));
      const viewer = c.var.caller.userId;
      const story = await squadStory(deps, {
        viewer,
        squad: AwardsSquad.parse(squadId),
        weekStart: AwardsWeek.parse(weekStart),
      });
      const { hottest } = story;
      const urls = await deps.photos.createViewUrls(
        (hottest?.photos ?? []).map((path) => PhotoPath.parse(path)),
        PHOTO_VIEW_SECONDS,
      );
      const hottestView = (top: TopCheckIn) => ({
        ...top,
        photos: top.photos.map((path) => {
          const url = urls.get(PhotoPath.parse(path));
          if (url === undefined) throw new Error(`No view URL was signed for ${path}.`);
          return { path, url: url.href };
        }),
        reactions: Object.entries(top.reactions).map(([kind, count]) => {
          const known = ReactionKind.safeParse(kind);
          return { kind, label: known.success ? REACTION_COPY[known.data][language] : kind, count };
        }),
      });
      const to = new Date(Date.parse(weekStart) + 6 * DAY).toISOString().slice(0, 10);
      return c.json(
        {
          version: 1 as const,
          language,
          status: story.status,
          squad: story.squad,
          week: { from: weekStart, to },
          ...(story.status === 'ready'
            ? {
                titles: story.members.map(({ member, titles }) => ({
                  member,
                  titles: [...titles],
                })),
              }
            : {}),
          ...(hottest === undefined ? {} : { hottest: hottestView(hottest) }),
        },
        200,
      );
    });
}
