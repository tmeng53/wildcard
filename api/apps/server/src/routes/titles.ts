import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { LocalDay, SportKey, WeekStart, type CheckIns } from '@wildcard/check-ins';
import {
  EquippedTeamBadge,
  EquippedTitle,
  JerseyNumber,
  MemberId,
  type Members,
  type Worn,
} from '@wildcard/members';
import { SquadId, SquadMemberUnknownError, type Squads } from '@wildcard/squads';
import {
  BadgeTone,
  TITLE_MAX,
  TitleNotWonError,
  wornOf,
  type ShownBoardTitle,
  type WeeklyAwards,
} from '@wildcard/weekly-awards';
import {
  BadgeNotHeldError,
  MemberId as RewardMember,
  type HeldBadge,
  type Rewards,
} from '@wildcard/unlocks';

import type { ReaderLanguage } from '@wildcard/language-model';

import { bodyVersion } from '../body-version.js';
import { squadFirstWeek } from '../flows/squad-weeks.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { readerLanguageOf } from '../reader-language.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { CharacterBody } from './character.js';
import { checkInTotalsFields } from './check-ins.js';
import { LocalizedWords } from './notices.js';
import { fuelGoalsBody, planDays } from './weekly-plans.js';

// 头衔徽章: the titles a member won in the Sunday 战报, each with its badge, on the back of their
// player card (徽章板); the one they wear on its front and beside their name on the home; and a
// squadmate's card.

/** A title's badge, as the app draws it. Plain text, so a new shape, colour or glyph is no break. */
export const TitleBadgeBody = z
  .strictObject({
    shape: z.string().meta({
      description:
        'The badge’s shape: `shield`, `hexagon`, `circle` or `scallop` today, and `ticket` ' +
        'for a team badge worn as one. An app that doesn’t know one draws a circle.',
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

/**
 * The title a member wears, wherever the API shows it beside them: a weekly title, or a team
 * badge worn as one (its name in the reader’s language on a ticket).
 */
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

/** A dedicated badge the team gives (捉虫队, 点子王), drawn as a ticket, apart from the titles. */
const TeamBadgeBody = z
  .strictObject({
    id: z.string().meta({ description: 'The badge’s id.', example: 'bug-hunter' }),
    name: LocalizedWords,
    glyph: z.string().meta({
      description: 'The SF Symbol on it, by name. An app whose iOS doesn’t have it draws a star.',
      example: 'ladybug.fill',
    }),
    tone: BadgeTone.meta({ description: 'Its colour, as #RRGGBB.', example: '#E65345' }),
    times: z.int().min(1).meta({ description: 'How many times the member got it: ×N.' }),
    latestAt: z.iso.datetime({ offset: true }).meta({
      description: 'When they got it the last time.',
      example: '2026-11-09T18:30:00.000Z',
    }),
  })
  .openapi('TeamBadge');

const boardFields = {
  teamBadges: z.array(TeamBadgeBody).meta({
    description:
      'The dedicated badges the Wildcard team gave the member (for feedback we used, say), ' +
      'the latest got first: tickets, shown apart from the titles. Never a title’s badge.',
  }),
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
        'before the first, and while a team badge is worn.',
    }),
  wornTeamBadge: z
    .string()
    .optional()
    .meta({
      description:
        'The team badge worn on the card’s front instead of a title, by its id. Left out unless ' +
        'the member chose one they hold.',
      example: 'idea-king',
    }),
};

const TitleBoard = z
  .strictObject({
    version: bodyVersion(1),
    ...boardFields,
    equipped: z
      .string()
      .optional()
      .meta({
        description:
          'The title the member chose to wear. Left out until they choose one, and while they wear ' +
          'a team badge.',
      }),
  })
  .openapi('TitleBoard');

const EquipTitle = z
  .strictObject({
    version: bodyVersion(1),
    title: EquippedTitle.nullable().meta({
      description:
        'A title the member has won, by its words, to wear on their card; null to wear the ' +
        'latest won again, or with `teamBadge`.',
    }),
    teamBadge: EquippedTeamBadge.optional().meta({
      description:
        'A team badge the member holds, by its id, to wear instead of a title; `title` must ' +
        'then be null. Left out by builds before it, whose save takes a worn team badge off.',
      example: 'idea-king',
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
    sports: z
      .array(
        z.strictObject({
          sport: SportKey,
          customSport: z.string().optional().meta({
            description: 'The custom sport’s name, for `sport: "custom"`.',
          }),
        }),
      )
      .optional()
      .meta({
        description:
          'Every sport the day’s 训练 logged, oldest first; only for `trained`, where it is ' +
          'always sent.',
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
        weekStart: WeekStart.meta({
          description:
            'This week’s Monday on the squad’s clock (小队时区), the same week for every squadmate.',
          example: '2026-11-02',
        }),
        days: planDays,
        marks: z
          .array(DayMarkBody)
          .min(7)
          .max(7)
          .meta({
            description:
              'How each day of this week went, Monday first: `trained` with the sport of the ' +
              'day’s latest 训练 (a 训练 wins over a 请假条), `disclaimer` for a 请假条, `none` ' +
              'for neither yet, from only the check-ins shared to this squad.',
          }),
        fuelGoals: fuelGoalsBody.optional(),
        firstWeek: WeekStart.optional().meta({
          description:
            'The Monday of the week they joined, in their time zone, which builds from before ' +
            '`squadFirstWeek` count their 出赛表 from. Missing before they save a profile.',
          example: '2026-10-12',
        }),
        squadFirstWeek: WeekStart.meta({
          description:
            'The Monday of the week this squad was made, on its clock: the week every 出赛表 in ' +
            'the squad counts as W1, so every card shows the same week number.',
          example: '2026-10-05',
        }),
        today: LocalDay.meta({
          description: 'Today on the squad’s clock, which their 出赛表 shades as 今天.',
          example: '2026-10-29',
        }),
      })
      .meta({ description: 'Their own 本周 x/y and this week’s 出赛表, on the card’s back.' }),
    ...boardFields,
  })
  .openapi('PlayerCard');

/** What a member wears and could wear: their titles, what they chose and the team's badges. */
interface WornInputs {
  readonly board: readonly ShownBoardTitle[];
  readonly equipped: string | null | undefined;
  readonly equippedTeamBadge: string | null | undefined;
  readonly teamBadges: readonly HeldBadge[];
}

/** The team badge a member wears: the one they chose, while they hold it. */
function wornBadgeOf({ equippedTeamBadge, teamBadges }: WornInputs): HeldBadge | undefined {
  return teamBadges.find(({ badge }) => badge.id === equippedTeamBadge);
}

/**
 * What a member wears beside their name (头衔): the team badge they chose while they hold it, its
 * name in the reader's language on a ticket, else their equipped or latest title.
 */
export function wornTitleOf(inputs: WornInputs, reader: ReaderLanguage) {
  const held = wornBadgeOf(inputs);
  if (held !== undefined) {
    return {
      title: held.badge.names[reader],
      badge: {
        shape: 'ticket',
        colour: held.badge.id,
        tone: held.badge.tone,
        glyph: held.badge.glyph,
      },
    };
  }
  const worn = wornOf(inputs.board, inputs.equipped);
  return worn === undefined ? undefined : { title: worn.title, badge: worn.badge };
}

/** The reader's language from the request, Simplified Chinese when it names none we write. */
export const readerOf = (header: string | undefined): ReaderLanguage =>
  readerLanguageOf(header) ?? 'zh-Hans';

/** A board as the API sends it; `speechIn` says which weeks' award lines and squad names it may carry. */
function wireBoard(inputs: WornInputs, speechIn: (squad: SquadId) => boolean) {
  const { board, equipped, teamBadges } = inputs;
  const wornBadge = wornBadgeOf(inputs);
  const worn = wornBadge === undefined ? wornOf(board, equipped) : undefined;
  return {
    teamBadges: teamBadges.map(({ badge, times, latestAt }) => ({
      id: badge.id,
      name: { zhHans: badge.names['zh-Hans'], en: badge.names.en, zhHant: badge.names['zh-Hant'] },
      glyph: badge.glyph,
      tone: badge.tone,
      times,
      latestAt: latestAt.toISOString(),
    })),
    titles: board.map(({ title, badge, weeks }) => ({
      title,
      badge,
      weeks: weeks.map(({ squad, squadName, weekStart, speech }) => ({
        weekStart,
        ...(speechIn(squad) ? { speech, ...(squadName === undefined ? {} : { squadName }) } : {}),
      })),
    })),
    ...(worn === undefined ? {} : { worn: worn.title }),
    ...(wornBadge === undefined ? {} : { wornTeamBadge: wornBadge.badge.id }),
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
  /** The dedicated badges the team gave, apart from the titles. */
  readonly rewards: Pick<Rewards, 'badgesOf'>;
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
        'Not a valid body, a title the member hasn’t won (`TITLE_NOT_WON`), a team badge they ' +
          'don’t hold or sent with a title (`BADGE_NOT_HELD`), or no profile saved yet ' +
          '(`PROFILE_MISSING`)',
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

  /** The member's board and what they chose to wear. */
  const boardOf = async (member: MemberId): Promise<WornInputs> => {
    const [boards, profile, teamBadges] = await Promise.all([
      deps.awards.boards([member]),
      deps.members.squadmates([member]),
      deps.rewards.badgesOf(RewardMember.parse(member)),
    ]);
    return {
      board: boards.get(member) ?? [],
      equipped: profile.get(member)?.equippedTitle,
      equippedTeamBadge: profile.get(member)?.equippedTeamBadge,
      teamBadges,
    };
  };

  const wireMine = (inputs: WornInputs) => ({
    version: 1 as const,
    ...wireBoard(inputs, () => true),
    ...(inputs.equipped === null || inputs.equipped === undefined
      ? {}
      : { equipped: inputs.equipped }),
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(getBoard, async (c) =>
      c.json(wireMine(await boardOf(MemberId.parse(c.var.caller.userId))), 200),
    )
    .openapi(putEquipped, async (c) => {
      const member = MemberId.parse(c.var.caller.userId);
      const { title, teamBadge } = c.req.valid('json');
      const { board, teamBadges } = await boardOf(member);
      let worn: Worn | null = null;
      if (teamBadge !== undefined) {
        if (title !== null || !teamBadges.some(({ badge }) => badge.id === teamBadge)) {
          throw new BadgeNotHeldError(teamBadge);
        }
        worn = { teamBadge };
      } else if (title !== null) {
        if (!board.some((each) => each.title === title)) throw new TitleNotWonError();
        worn = { title };
      }
      await deps.members.wear(member, worn);
      return c.json(
        wireMine({ board, equipped: title, equippedTeamBadge: teamBadge ?? null, teamBadges }),
        200,
      );
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
      const squadZone = (await deps.squads.timeZonesAt([squad.id], new Date()))(squad.id);
      const viewer = MemberId.parse(c.var.caller.userId);
      const [boards, profiles, totals, week, teamBadges, squadWeek, streaks] = await Promise.all([
        deps.awards.boards([memberId]),
        deps.members.squadmates([memberId]),
        // A squadmate sees only what the member sent to this squad (posted or only recorded),
        // nothing from before they joined it. The member's own card counts everything, as 我 does.
        viewer === memberId
          ? deps.checkIns.totals(memberId)
          : deps.checkIns.totalsSharedTo({ member: memberId, squad: squadId }),
        deps.checkIns.memberWeek({
          member: memberId,
          viewer: MemberId.parse(c.var.caller.userId),
          squad: squadId,
          squadZone,
        }),
        deps.rewards.badgesOf(RewardMember.parse(memberId)),
        squadFirstWeek(deps.squads, squad),
        // As the totals: a squadmate sees only what was shared to this squad.
        deps.checkIns.currentStreaks({
          member: memberId,
          ...(viewer === memberId ? {} : { squad: squadId }),
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
          streaks,
          week: {
            ...week,
            squadFirstWeek: squadWeek,
            days: [...week.days],
            marks: week.marks.map((mark) =>
              mark.status === 'trained' ? { ...mark, sports: [...mark.sports] } : mark,
            ),
          },
          ...wireBoard(
            {
              board: boards.get(memberId) ?? [],
              equipped: profile?.equippedTitle,
              equippedTeamBadge: profile?.equippedTeamBadge,
              teamBadges,
            },
            (squad) => squad === squadId,
          ),
        },
        200,
      );
    });
}
