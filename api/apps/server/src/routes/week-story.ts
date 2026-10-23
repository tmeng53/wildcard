import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { Emoji, LocalDay, SquadId, WeekStart } from '@wildcard/check-ins';
import {
  AWARD_MOVES,
  CheckInKind,
  ENDING_LINE_MAX,
  HEADLINE_MAX,
  HOTTEST_LINE_MAX,
  MEALS_LINE_MAX,
  MY_WEEK_LINE_MAX,
  SPEECH_MAX,
  TITLE_MAX,
  TITLES_MAX,
  SquadId as AwardsSquad,
  WeekStart as AwardsWeek,
} from '@wildcard/weekly-awards';

import { bodyVersion } from '../body-version.js';
import {
  nudgeOrganisers,
  squadStory,
  type SquadStory,
  type WeeklyAwardsDependencies,
} from '../flows/weekly-awards.js';
import { PhotoPath, type PhotoStorage, type VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

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

/** Words an AI writes on a page: only once `ready`, and only when it wrote them. */
const line = (max: number, description: string) =>
  z
    .string()
    .min(1)
    .optional()
    .meta({
      description: `${description}, at most ${String(max)} characters. Written by the AI: only once \`ready\`, and missing when it wrote none.`,
    });

/** A move an AI picks for a page: only once `ready`. */
const aiMove = (description: string) =>
  move(`${description} Picked by the AI: only once \`ready\`.`).optional();

const count = (description: string) => z.int().min(0).meta({ description });

const Podium = z
  .strictObject({
    champion: z.uuid().meta({ description: 'The crown winner, in the middle.' }),
    sides: z
      .array(z.uuid())
      .max(2)
      .meta({ description: 'Up to 2 others who finished their plan, left then right.' }),
    speech: line(SPEECH_MAX, 'The champion’s award line (颁奖词)'),
    championMove: aiMove('The champion’s move after the crown toss.'),
    sideMove: aiMove('The sides’ move.'),
  })
  .openapi('StoryPodium');

const MyWeek = z
  .strictObject({
    plan: count('Training days in the reader’s plan.'),
    days: z
      .array(
        z
          .strictObject({
            day: LocalDay,
            kind: z.enum(['trained', 'rest', 'disclaimer', 'none']).meta({
              description:
                '`trained` wins over `disclaimer` (a 请假条), which wins over a planned `rest` day; ' +
                '`none` is a day with nothing checked in.',
            }),
            sport: z.string().optional().meta({
              description:
                'For a trained day: its first 练了’s sport key, or the name of the member’s own.',
            }),
          })
          .openapi('StoryDay'),
      )
      .min(7)
      .max(7)
      .meta({ description: 'Monday first.' }),
    line: line(MY_WEEK_LINE_MAX, 'A line about the reader’s week'),
    healthyMeals: count('健康餐 they checked in.'),
    cheatMeals: count('坦白放纵餐 they checked in.'),
    reactionsReceived: count('Teammates’ reactions on their check-ins.'),
  })
  .openapi('StoryMyWeek');

const Meals = z
  .strictObject({
    healthy: count('The squad’s 健康餐.'),
    cheat: count('The squad’s 坦白放纵餐.'),
    eaters: z
      .array(
        z.strictObject({
          member: z.uuid(),
          more: z.enum(['healthy', 'cheat']).meta({
            description: 'What they checked in more of, `healthy` on a tie.',
          }),
        }),
      )
      .min(1)
      .meta({ description: 'Everyone who checked in a meal, in the order they joined.' }),
    line: line(MEALS_LINE_MAX, 'A line about the squad’s meals'),
  })
  .openapi('StoryMeals');

const BestDisclaimer = z
  .strictObject({
    checkIn: z.uuid(),
    author: z.uuid(),
    text: z.string().min(1),
    reactions: z.int().min(1).meta({ description: 'Teammates’ reactions on it.' }),
    authorMove: aiMove('The author acting the note out.'),
    squadMove: aiMove('How two teammates react: `laugh`, `pump` or `wave`.'),
  })
  .openapi('StoryBestDisclaimer');

const Ending = z
  .strictObject({
    done: count('Days the squad trained, added up over the members.'),
    plan: count('Days the squad planned, added up over the members.'),
    headline: line(HEADLINE_MAX, 'The headline, such as 稳了 or 差一点'),
    line: line(ENDING_LINE_MAX, 'A funny line about the week, never guilt'),
    move: aiMove('The squad’s move.'),
  })
  .openapi('StoryEnding');

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
          emoji: Emoji.meta({ description: 'Any one emoji.', example: '❤️' }),
          count: z.int().min(1),
        }),
      )
      .meta({
        description:
          'Teammates’ reactions on it, one entry an emoji, most-used first, as they stood at ' +
          'the awards.',
      }),
    line: line(HOTTEST_LINE_MAX, 'A line answering the check-in'),
    move: aiMove('The reader’s move next to it.'),
  })
  .openapi('StoryHottest');

const storyFields = {
  version: bodyVersion(1),
  squad: z.strictObject({ id: z.uuid(), name: z.string() }),
  week: z.strictObject({ from: WeekStart, to: LocalDay }),
  podium: Podium.optional().meta({
    description:
      '领奖台: missing when nobody trained at least as many days as they planned (and one).',
  }),
  myWeek: MyWeek.optional().meta({
    description: '你的一周, the signed-in member’s: missing when they checked in nothing.',
  }),
  hottest: Hottest.optional().meta({
    description:
      'The signed-in member’s check-in with the most reactions at the awards, the latest on a ' +
      'tie; while `pending`, as it stands now. Missing when none of theirs had any.',
  }),
  meals: Meals.optional().meta({ description: '吃了: missing when nobody checked in a meal.' }),
  bestDisclaimer: BestDisclaimer.optional().meta({
    description:
      '最佳请假条: the one with the most reactions (at least one), the earliest on a tie; ' +
      'missing when none had any.',
  }),
  ending: Ending.optional().meta({
    description:
      '这一周: missing when nobody trained, so a quiet week isn’t told how short it fell.',
  }),
};

export const WeekStoryBody = z
  .discriminatedUnion('status', [
    z
      .strictObject({
        ...storyFields,
        status: z.literal('ready'),
        titles: z
          .array(
            z.strictObject({
              member: z.uuid(),
              titles: z
                .array(Title)
                .min(1)
                .max(TITLES_MAX)
                .meta({ description: 'The best first.' }),
            }),
          )
          .meta({
            description:
              'Every member still in the squad who checked in before the awards, in the order ' +
              'they joined, with 1 to 3 titles. Empty when nobody checked in. The weekly ' +
              'poster’s stickers read these too.',
          }),
        order: z
          .array(
            z.enum(['podium', 'titles', 'myWeek', 'hottest', 'meals', 'bestDisclaimer', 'ending']),
          )
          .optional()
          .meta({
            description:
              'The pages this story has, in the order the AI picked: `podium` and `titles` first, ' +
              '`ending` last. Missing when the AI picked none (play the default order).',
          }),
      })
      .meta({ description: 'The week’s titles are written.' }),
    z.strictObject({ ...storyFields, status: z.literal('pending') }).meta({
      description:
        'The titles are due but not written yet (the AI failed, or hasn’t reached the squad): ' +
        'only the titles page waits, showing that the organisers are out of funds with a ' +
        'button that nudges them (`POST …/story/nudge`); every other page shows as usual, ' +
        'without the AI’s lines and moves, in the default order. Read again later.',
    }),
  ])
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
      'awards. Only for members of the squad.',
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
      const hottestView = (top: NonNullable<SquadStory['hottest']>) => ({
        ...top,
        photos: top.photos.map((path) => {
          const url = urls.get(PhotoPath.parse(path));
          if (url === undefined) throw new Error(`No view URL was signed for ${path}.`);
          return { path, url: url.href };
        }),
        reactions: Object.entries(top.reactions)
          .sort(([, a], [, b]) => b - a)
          .map(([emoji, count]) => ({ emoji: Emoji.parse(emoji), count })),
      });
      const to = new Date(Date.parse(weekStart) + 6 * DAY).toISOString().slice(0, 10);
      const fields = {
        version: 1 as const,
        squad: story.squad,
        week: { from: weekStart, to },
        ...(story.podium === undefined
          ? {}
          : { podium: { ...story.podium, sides: [...story.podium.sides] } }),
        ...(story.myWeek === undefined
          ? {}
          : { myWeek: { ...story.myWeek, days: [...story.myWeek.days] } }),
        ...(hottest === undefined ? {} : { hottest: hottestView(hottest) }),
        ...(story.meals === undefined
          ? {}
          : { meals: { ...story.meals, eaters: [...story.meals.eaters] } }),
        ...(story.bestDisclaimer === undefined ? {} : { bestDisclaimer: story.bestDisclaimer }),
        ...(story.ending === undefined ? {} : { ending: story.ending }),
      };
      return c.json(
        story.status === 'ready'
          ? {
              ...fields,
              status: 'ready' as const,
              titles: story.members.map(({ member, titles }) => ({
                member,
                titles: [...titles],
              })),
              ...(story.order === undefined ? {} : { order: [...story.order] }),
            }
          : { ...fields, status: 'pending' as const },
        200,
      );
    });
}
