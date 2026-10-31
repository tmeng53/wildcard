import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { Emoji, LocalDay, SquadId, WeekStart } from '@wildcard/check-ins';
import {
  AwardMove,
  CheckInKind,
  SPEECH_MAX,
  TITLE_MAX,
  TITLES_MAX,
  SquadId as AwardsSquad,
  WeekStart as AwardsWeek,
  type TopCheckIn,
} from '@wildcard/weekly-awards';

import { Scene } from '@wildcard/squads';

import { bodyVersion } from '../body-version.js';
import {
  nudgeOrganisers,
  squadStory,
  type WeeklyAwardsDependencies,
} from '../flows/weekly-awards.js';
import { PhotoPath, type PhotoStorage, type VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { CharacterBody } from './character.js';

/** How long a photo's view URL works. The app reads the story again for fresh ones. */
const PHOTO_VIEW_SECONDS = 60 * 60;

const DAY = 86_400_000;

const move = (description: string) =>
  z
    .string()
    .min(1)
    .meta({
      description:
        `${description} Today one of ${AwardMove.options
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
          emoji: Emoji.meta({ description: 'Any one emoji.', example: '❤️' }),
          count: z.int().min(1),
        }),
      )
      .meta({
        description:
          'Teammates’ reactions on it, one entry an emoji, most-used first, as they stood at ' +
          'the awards.',
      }),
  })
  .openapi('StoryHottest');

const count = z.int().min(0);

const StoryDay = z
  .strictObject({
    day: LocalDay,
    kind: z.enum(['trained', 'rest', 'disclaimer', 'none']).meta({
      description: 'A 练了 wins over a 请假条, which wins over a planned rest day.',
    }),
    sport: z.string().optional().meta({
      description:
        'For a trained day: its first 练了’s listed sport; missing for a sport of the member’s own.',
    }),
  })
  .openapi('StoryDay');

const storyFields = {
  version: bodyVersion(1),
  squad: z
    .strictObject({
      id: z.uuid(),
      name: z.string().meta({ description: 'The squad’s name that week.' }),
    })
    .openapi('StorySquad'),
  week: z.strictObject({ from: WeekStart, to: LocalDay }).openapi('StoryWeek'),
  scene: Scene.meta({
    description: 'The scene the squad trained on that week: the story takes its colours.',
  }),
  members: z
    .array(
      z
        .strictObject({
          member: z.uuid(),
          // Their character as it was that week; missing when they had none.
          character: CharacterBody.optional(),
        })
        .openapi('StoryMember'),
    )
    .meta({
      description:
        'Everyone in the squad at the awards, in the order they joined: someone who joined ' +
        'later isn’t here, someone who left since is. A deleted account is left out.',
    }),
  podium: z
    .strictObject({ champion: z.uuid(), sides: z.array(z.uuid()).max(2) })
    .openapi('StoryPodium')
    .optional()
    .meta({
      description:
        '领奖台: the crown winner (most days trained) in the middle, up to 2 others who finished ' +
        'their plan beside. Missing when nobody did either.',
    }),
  myWeek: z
    .strictObject({
      plannedDays: count,
      trainedDays: count,
      days: z.array(StoryDay).length(7).meta({ description: 'Monday first.' }),
      healthyMeals: count,
      cheatMeals: count,
      reactionsReceived: count,
    })
    .openapi('StoryMyWeek')
    .optional()
    .meta({
      description:
        '你的一周: the signed-in member’s week. Missing when they checked in nothing, or weren’t ' +
        'in the squad at the awards.',
    }),
  hottest: Hottest.optional().meta({
    description:
      'The signed-in member’s check-in with the most reactions at the awards, the latest on a ' +
      'tie. No AI writes it. Missing when none of theirs had any, or it was deleted since.',
  }),
  meals: z
    .strictObject({
      healthy: count,
      cheat: count,
      eaters: z.array(z.strictObject({ member: z.uuid(), more: z.enum(['healthy', 'cheat']) })),
    })
    .openapi('StoryMeals')
    .optional()
    .meta({
      description:
        '吃了: the squad’s meals, and each member who logged one eating what they logged more of ' +
        '(健康餐 on a tie). Missing when nobody logged a meal.',
    }),
  bestDisclaimer: z
    .strictObject({
      checkIn: z.uuid(),
      author: z.uuid(),
      text: z.string(),
      reactions: z.int().min(1),
    })
    .openapi('StoryBestDisclaimer')
    .optional()
    .meta({
      description:
        '最佳请假条: the one with the most reactions. Missing when none had any, or it was deleted.',
    }),
  ending: z
    .strictObject({ done: count, plan: count })
    .openapi('StoryEnding')
    .optional()
    .meta({
      description:
        '这一周: the squad’s days trained against its plans. Missing when nobody trained, so a ' +
        'quiet week isn’t told how short it fell.',
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
              'Every member in the squad at the awards who checked in before them and agreed to ' +
              'AI use, in the order they joined, with 1 to 3 titles. Empty when nobody checked ' +
              'in. The weekly poster’s stickers read these too.',
          }),
      })
      .meta({ description: 'The week’s titles are written.' }),
    z.strictObject({ ...storyFields, status: z.literal('pending') }).meta({
      description:
        'The titles are due but not written yet (the AI failed, or hasn’t reached the squad): ' +
        'only the titles page waits, showing that the organisers are out of funds with a ' +
        'button that nudges them (`POST …/story/nudge`); every other page is frozen and shows ' +
        'as usual. Read again later.',
    }),
  ])
  .openapi('WeekStory');

/** `GET /squads/{squadId}/weeks/{weekStart}/story`: a squad's Sunday 战报 story. */
export function weekStory(
  deps: Pick<
    WeeklyAwardsDependencies,
    'checkIns' | 'squads' | 'members' | 'awards' | 'push' | 'admins' | 'clock' | 'log'
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
    summary: 'A squad’s weekly 战报 (每周战报), frozen at the week’s awards',
    description:
      'Frozen once for the whole squad on Sunday at 8pm Eastern: who was in the squad then, ' +
      'that week’s scene, and every page from the check-ins and reactions made before then. ' +
      'Nothing that happens later changes it (a member joining or leaving, a late check-in or ' +
      'reaction, a new look or scene), except that a deleted account or post takes its own ' +
      'words and photos with it. The AI’s titles for each member who checked in come within ' +
      'the hour (`pending` until then). Check-ins made later still count for the week’s ' +
      'summary, only not here. Only for members of the squad now.',
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
      const hottest = story.mine?.hottest;
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
        reactions: Object.entries(top.reactions)
          .sort(([, a], [, b]) => b - a)
          .map(([emoji, count]) => ({ emoji: Emoji.parse(emoji), count })),
      });
      const to = new Date(Date.parse(weekStart) + 6 * DAY).toISOString().slice(0, 10);
      const mine = story.mine;
      const eaters = story.members
        .filter(({ healthyMeals, cheatMeals }) => healthyMeals + cheatMeals > 0)
        .map(({ member, healthyMeals, cheatMeals }) => ({
          member,
          more: cheatMeals > healthyMeals ? ('cheat' as const) : ('healthy' as const),
        }));
      const fields = {
        version: 1 as const,
        squad: story.squad,
        week: { from: weekStart, to },
        scene: Scene.parse(story.scene),
        members: story.members.map(({ member, character }) => {
          const parsed = CharacterBody.nullable().parse(character);
          return { member, ...(parsed === null ? {} : { character: parsed }) };
        }),
        ...(story.podium === undefined
          ? {}
          : { podium: { champion: story.podium.champion, sides: [...story.podium.sides] } }),
        ...(mine?.checkedIn !== true
          ? {}
          : {
              myWeek: {
                plannedDays: mine.plannedDays,
                trainedDays: mine.trainedDays,
                days: [...mine.days],
                healthyMeals: mine.healthyMeals,
                cheatMeals: mine.cheatMeals,
                reactionsReceived: mine.reactionsReceived,
              },
            }),
        ...(hottest === undefined ? {} : { hottest: hottestView(hottest) }),
        ...(story.meals === undefined || eaters.length === 0
          ? {}
          : { meals: { ...story.meals, eaters } }),
        ...(story.bestDisclaimer === undefined ? {} : { bestDisclaimer: story.bestDisclaimer }),
        ...(story.ending === undefined ? {} : { ending: story.ending }),
      };
      return c.json(
        story.status === 'ready'
          ? {
              ...fields,
              status: 'ready' as const,
              titles: story.titles.map(({ member, titles }) => ({
                member,
                titles: [...titles],
              })),
            }
          : { ...fields, status: 'pending' as const },
        200,
      );
    });
}
