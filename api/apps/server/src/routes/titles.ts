import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { SportKey, WeekStart, type CheckIns } from '@wildcard/check-ins';
import { EquippedTitle, JerseyNumber, MemberId, type Members } from '@wildcard/members';
import { SquadId, SquadMemberUnknownError, type Squads } from '@wildcard/squads';
import {
  BadgeTone,
  TITLE_MAX,
  TitleNotWonError,
  wornOf,
  type ShownBoardTitle,
  type WeeklyAwards,
} from '@wildcard/weekly-awards';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { CharacterBody } from './character.js';
import { checkInTotalsFields } from './check-ins.js';
import { fuelGoalsBody, planDays } from './weekly-plans.js';

// 头衔徽章: the titles a member won in the Sunday 战报, each with its badge, on the back of their
// player card (徽章板); the one they wear on its front and beside their name on the home; and a
// squadmate's card.

/** A title's badge, as the app draws it. Plain text, so a new shape, colour or glyph is no break. */
export const TitleBadgeBody = z
  .strictObject({
    shape: z.string().meta({
      description:
        'The badge’s shape: `shield`, `hexagon`, `circle` or `scallop` today. An app that ' +
        'doesn’t know one draws a circle.',
      example: 'shield',
    }),
    colour: z.string().meta({
      description:
        'Its colour, by its id in the badge catalog (`track`). Builds before `tone` paint it ' +
        'by the scene of that id, and the gym’s for any other.',
      example: 'track',
    }),
    tone: BadgeTone.optional().meta({
      description:
        'Its colour itself, as #RRGGBB, from the badge catalog: what the app paints it in. Left ' +
        'out by older servers and for a colour the catalog gives no tone, which the app then ' +
        'paints like `colour` for builds before `tone`.',
      example: '#E65345',
    }),
    glyph: z.string().meta({
      description: 'The SF Symbol on it, by name. An app whose iOS doesn’t have it draws a star.',
      example: 'sun.max.fill',
    }),
  })
  .openapi('TitleBadge');

const titleWords = z.string().meta({
  description: `The title’s words, at most ${String(TITLE_MAX)} characters.`,
  example: '早八战神',
});

/** The title a member wears, wherever the API shows it beside them. */
export const WornTitleBody = z
  .strictObject({ title: titleWords, badge: TitleBadgeBody })
  .openapi('WornTitle');

const BoardTitleBody = z
  .strictObject({
    title: titleWords,
    // The badge it was last won with.
    badge: TitleBadgeBody,
    weeks: z
      .array(
        z.strictObject({
          weekStart: z.iso.date().meta({ description: 'The Monday of the week it was won.' }),
          squadName: z
            .string()
            .optional()
            .meta({
              description:
                'The name of the squad it was won in, as that week’s 战报 froze it. Left out for ' +
                'a week won before 战报 froze, and, on a squadmate’s card, for weeks won in ' +
                'another squad.',
              example: '早八战队',
            }),
          speech: z
            .string()
            .optional()
            .meta({
              description:
                'Its award line (颁奖词) that week. On a squadmate’s card, left out for weeks won ' +
                'in another squad.',
            }),
        }),
      )
      .min(1)
      .meta({ description: 'Every week it was won, the latest first: ×N on the board.' }),
  })
  .openapi('BoardTitle');

const boardFields = {
  titles: z.array(BoardTitleBody).meta({
    description:
      'Every title won, in all the member’s squads, one per title by its words, the latest ' +
      'won first.',
  }),
  worn: z
    .string()
    .optional()
    .meta({
      description:
        'The title worn on the card’s front: the one equipped, else the latest won. Left out ' +
        'before the first.',
    }),
};

const TitleBoard = z
  .strictObject({
    version: bodyVersion(1),
    ...boardFields,
    equipped: z.string().optional().meta({
      description: 'The title the member chose to wear. Left out until they choose one.',
    }),
  })
  .openapi('TitleBoard');

const EquipTitle = z
  .strictObject({
    version: bodyVersion(1),
    title: EquippedTitle.nullable().meta({
      description:
        'A title the member has won, by its words, to wear on their card; null to wear the ' +
        'latest won again.',
    }),
  })
  .openapi('EquipTitle');

const DayMarkBody = z
  .strictObject({
    status: z.enum(['trained', 'disclaimer', 'none']),
    sport: SportKey.optional().meta({ description: 'The 训练’s sport; only for `trained`.' }),
    customSport: z.string().optional().meta({
      description: 'The custom sport’s name, for `sport: "custom"`.',
    }),
  })
  .openapi('DayMark');

const PlayerCardBody = z
  .strictObject({
    version: bodyVersion(1),
    member: z.uuid(),
    // Left out rather than null: the Swift generator can't read a nullable reference.
    character: CharacterBody.optional(),
    jerseyNumber: JerseyNumber.optional().meta({
      description: 'The number they picked for their card. Left out until they pick one.',
    }),
    squadPlace: z.int().positive().meta({
      description:
        'Their place in this squad, the first to join being 1: the number shown without a pick.',
    }),
    joinedAt: z.iso.datetime().optional().meta({
      description: 'When they signed up, in UTC. Left out before they saved a profile.',
    }),
    ...checkInTotalsFields,
    week: z
      .strictObject({
        trainedDays: z.int().nonnegative().meta({
          description: 'Days they trained this week, from all their check-ins wherever they went.',
        }),
        plannedDays: z.int().nonnegative().meta({
          description: 'Days their plan trains this week, from the day they joined on.',
        }),
        // The card's back, their 出赛表: this week only, never another week's.
        weekStart: WeekStart.optional().meta({
          description: 'This week’s Monday, in their time zone. Left out by older servers.',
          example: '2026-11-02',
        }),
        days: planDays.optional(),
        marks: z
          .array(DayMarkBody)
          .min(7)
          .max(7)
          .optional()
          .meta({
            description:
              'How each day of this week went, Monday first: `trained` with the sport of the ' +
              'day’s latest 训练 (a 训练 wins over a 请假条), `disclaimer` for a 请假条, `none` ' +
              'for neither yet, from only the check-ins shared to this squad. Left out by older ' +
              'servers.',
          }),
        fuelGoals: fuelGoalsBody.optional(),
        firstWeek: WeekStart.optional().meta({
          description:
            'The Monday of the week they joined, in their time zone, which their 出赛表 counts ' +
            'as W1. Missing before they save a profile, and from older servers.',
          example: '2026-10-12',
        }),
      })
      .optional()
      .meta({
        description:
          'Their own 本周 x/y, in their time zone. Left out by older servers; the app then ' +
          'shows no week.',
      }),
    ...boardFields,
  })
  .openapi('PlayerCard');

/** A board as the API sends it; `speechIn` says which weeks' award lines and squad names it may carry. */
function wireBoard(
  {
    board,
    equipped,
  }: { readonly board: readonly ShownBoardTitle[]; readonly equipped: string | null | undefined },
  speechIn: (squad: SquadId) => boolean,
) {
  const worn = wornOf(board, equipped);
  return {
    titles: board.map(({ title, badge, weeks }) => ({
      title,
      badge,
      weeks: weeks.map(({ squad, squadName, weekStart, speech }) => ({
        weekStart,
        ...(speechIn(squad) ? { speech, ...(squadName === undefined ? {} : { squadName }) } : {}),
      })),
    })),
    ...(worn === undefined ? {} : { worn: worn.title }),
  };
}

const unauthorized = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/**
 * `GET /me/titles`, `PUT /me/equipped-title` and `GET /squads/{squadId}/members/{memberId}/card`:
 * the signed-in member's badge board, the title they wear, and a squadmate's player card.
 */
export function titles(deps: {
  readonly verifyToken: VerifyToken;
  readonly members: Members;
  readonly squads: Squads;
  readonly checkIns: CheckIns;
  readonly awards: WeeklyAwards;
}) {
  const getBoard = createRoute({
    method: 'get',
    path: '/me/titles',
    operationId: 'getMyTitles',
    summary: 'The signed-in member’s badge board',
    description:
      'Every weekly title they won, with its badge, the weeks and award lines (徽章板), and the ' +
      'one they wear.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: { description: 'The board', content: { 'application/json': { schema: TitleBoard } } },
      ...unauthorized,
    },
  });
  const putEquipped = createRoute({
    method: 'put',
    path: '/me/equipped-title',
    operationId: 'putMyEquippedTitle',
    summary: 'Wear a title on the signed-in member’s card',
    description:
      'Wears one of the member’s titles on their player card and beside their name on the ' +
      'home, logged with their profile. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { body: { required: true, content: { 'application/json': { schema: EquipTitle } } } },
    responses: {
      200: { description: 'Worn', content: { 'application/json': { schema: TitleBoard } } },
      400: problem(
        'Not a valid body, a title the member hasn’t won (`TITLE_NOT_WON`), or no profile ' +
          'saved yet (`PROFILE_MISSING`)',
      ),
      ...jsonBodyFailures,
      ...unauthorized,
    },
  });
  const getCard = createRoute({
    method: 'get',
    path: '/squads/{squadId}/members/{memberId}/card',
    operationId: 'getSquadmateCard',
    summary: 'A squadmate’s player card',
    description:
      'What a squadmate’s card shows, front and back: their character, number, lifetime ' +
      'counts and badge board, with award lines only from weeks won in this squad. Only for ' +
      'members of the squad, about a member of it.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId, memberId: MemberId }) },
    responses: {
      200: { description: 'The card', content: { 'application/json': { schema: PlayerCardBody } } },
      400: problem('Not a valid squad or member id'),
      403: problem('The signed-in member isn’t in this squad'),
      404: problem('That member isn’t in this squad (`SQUAD_MEMBER_UNKNOWN`)'),
      ...unauthorized,
    },
  });

  /** The member's board and the title they equipped. */
  const boardOf = async (member: MemberId) => {
    const [boards, profile] = await Promise.all([
      deps.awards.boards([member]),
      deps.members.squadmates([member]),
    ]);
    return { board: boards.get(member) ?? [], equipped: profile.get(member)?.equippedTitle };
  };

  const wireMine = ({
    board,
    equipped,
  }: {
    readonly board: readonly ShownBoardTitle[];
    readonly equipped: string | null | undefined;
  }) => ({
    version: 1 as const,
    ...wireBoard({ board, equipped }, () => true),
    ...(equipped === null || equipped === undefined ? {} : { equipped }),
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(getBoard, async (c) =>
      c.json(wireMine(await boardOf(MemberId.parse(c.var.caller.userId))), 200),
    )
    .openapi(putEquipped, async (c) => {
      const member = MemberId.parse(c.var.caller.userId);
      const { title } = c.req.valid('json');
      const { board } = await boardOf(member);
      if (title !== null && !board.some((each) => each.title === title)) {
        throw new TitleNotWonError();
      }
      await deps.members.equipTitle(member, title);
      return c.json(wireMine({ board, equipped: title }), 200);
    })
    .openapi(getCard, async (c) => {
      const { squadId, memberId } = c.req.valid('param');
      // Refuses a viewer outside the squad.
      const squad = await deps.squads.find({
        squad: squadId,
        viewer: MemberId.parse(c.var.caller.userId),
      });
      const place = squad.members.findIndex(({ member }) => member === memberId);
      if (place < 0) throw new SquadMemberUnknownError(memberId);
      const [boards, profiles, totals, week] = await Promise.all([
        deps.awards.boards([memberId]),
        deps.members.squadmates([memberId]),
        deps.checkIns.totals(memberId),
        deps.checkIns.memberWeek({
          member: memberId,
          viewer: MemberId.parse(c.var.caller.userId),
          squad: squadId,
        }),
      ]);
      const profile = profiles.get(memberId);
      return c.json(
        {
          version: 1 as const,
          member: memberId,
          ...(profile?.character == null ? {} : { character: profile.character }),
          ...(profile?.jerseyNumber == null ? {} : { jerseyNumber: profile.jerseyNumber }),
          squadPlace: place + 1,
          ...(profile === undefined ? {} : { joinedAt: profile.joinedAt.toISOString() }),
          ...totals,
          week: {
            ...week,
            days: [...week.days],
            marks: [...week.marks],
          },
          ...wireBoard(
            { board: boards.get(memberId) ?? [], equipped: profile?.equippedTitle },
            (squad) => squad === squadId,
          ),
        },
        200,
      );
    });
}
