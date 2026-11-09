import { createHash } from 'node:crypto';

import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import type { Art } from '@wildcard/art';
import type { QuickReactionsAdmin } from '@wildcard/check-ins';
import type { DiceLinesAdmin } from '@wildcard/disclaimer-drafts';
import type { Scenes } from '@wildcard/scenes';
import type { SportCatalog, Sports } from '@wildcard/sports';
import type { MinimumBuilds, Switches } from '@wildcard/switches';
import type { UnlocksAdmin } from '@wildcard/unlocks';

import { bodyVersion } from '../body-version.js';
import { problem } from '../problem.js';
import { rateLimited } from '../rate-limited.js';
import type { PublicRoutes } from './squads.js';

/**
 * One part of the catalog: data the app shows that lives in the database, so it changes without
 * an app release. Its module keeps the table; `main.ts` lists the sections.
 */
export interface CatalogSection<Schema extends z.ZodType = z.ZodType> {
  /** Its key in the body. */
  readonly name: string;
  readonly schema: Schema;
  /** The section as it stands now. */
  readonly load: () => Promise<z.input<Schema>>;
}

const Names = z
  .looseObject({
    zhHans: z.string().meta({ description: 'Simplified Chinese.', example: '跑步' }),
    en: z.string().meta({ description: 'English.', example: 'Run' }),
    zhHant: z.string().meta({ description: 'Traditional Chinese (Taiwan).', example: '跑步' }),
  })
  .openapi('CatalogNames');

const sportIds = (description: string) =>
  z.array(z.string()).meta({ description: `${description} Sport ids, in order.` });

export const SportsCatalog = z
  .looseObject({
    categories: z
      .array(
        z.looseObject({
          id: z.string().meta({ example: 'runWalk' }),
          names: Names,
          color: z
            .string()
            .optional()
            .meta({
              description:
                'The colour its sports’ 成绩条, post blocks, routes and charts wear, with white ' +
                'on it: `#RRGGBB`. Always sent; optional so a copy an app kept from before ' +
                'colours still reads (its sports then wear the gym’s steel).',
              example: '#E65345',
            }),
          sports: z.array(
            z.looseObject({
              id: z.string().meta({
                description:
                  'What a 训练 or a planned day sends as `sport`. Never changes, and a sport is ' +
                  'never removed.',
                example: 'run',
              }),
              names: Names,
              // The name on a card or poster row, for a sport whose name is too long there;
              // without it, `names`. A plain reference, so the app's type is `CatalogNames`.
              shortNames: Names.optional(),
              icon: z.string().meta({
                description:
                  'An SF Symbol name. One the phone’s iOS doesn’t have shows a general figure.',
                example: 'figure.run',
              }),
              offered: z.boolean().meta({
                description:
                  'False for a sport the pickers no longer offer: show it only for check-ins ' +
                  'and plans that already name it.',
              }),
            }),
          ),
        }),
      )
      .meta({ description: 'The picker’s tabs, in order, each with its sports in order.' }),
    picks: z
      .looseObject({
        signUpCommon: sportIds('Sign-up’s 最常见 grid.'),
        checkInQuick: sportIds('A 训练’s quick picks, before the whole list.'),
      })
      .meta({ description: 'The short lists some screens show before the whole list.' }),
  })
  .openapi('SportsCatalog');

/** The `sports` section: every sport any picker shows. */
export function sportsSection(sports: Sports): CatalogSection<typeof SportsCatalog> {
  return {
    name: 'sports',
    schema: SportsCatalog,
    load: async () => wireSports(await sports.catalog()),
  };
}

const wireSports = (catalog: SportCatalog): z.input<typeof SportsCatalog> => ({
  categories: catalog.categories.map(({ id, names, color, sports }) => ({
    id,
    names: { ...names },
    color,
    sports: sports.map(({ shortNames, ...sport }) => ({
      ...sport,
      names: { ...sport.names },
      ...(shortNames === undefined ? {} : { shortNames: { ...shortNames } }),
    })),
  })),
  picks: {
    signUpCommon: [...catalog.picks.signUpCommon],
    checkInQuick: [...catalog.picks.checkInQuick],
  },
});

export const DisclaimerDiceCatalog = z
  .looseObject({
    lines: z.array(Names).meta({
      description: 'Every line, in no set order: the app rolls three different ones at a time.',
    }),
  })
  .openapi('DisclaimerDiceCatalog');

/** The `disclaimerDice` section: the 请假条 lines the app rolls when the AI can't write. */
export function disclaimerDiceSection(
  dice: Pick<DiceLinesAdmin, 'current'>,
): CatalogSection<typeof DisclaimerDiceCatalog> {
  return {
    name: 'disclaimerDice',
    schema: DisclaimerDiceCatalog,
    load: async () => ({ lines: (await dice.current()).lines.map((line) => ({ ...line })) }),
  };
}

export const ArtCatalog = z
  .looseObject({
    generation: z
      .int()
      .min(0)
      .meta({
        description:
          'The newest change’s number. The app uses a generation only once it has every file of ' +
          'it, and keeps the one it has until then.',
      }),
    baseUrl: z.url().meta({
      description: 'Where each file downloads from: this URL, then `<sha256>.<extension>`.',
      example: 'https://example.supabase.co/storage/v1/object/public/art/',
    }),
    files: z
      .array(
        z.looseObject({
          path: z.string().meta({
            description:
              'Where the file goes in the app’s art tree (`avatar/…` over the character’s ' +
              'bundled folder, `coaches/…` over the coaches’ characters, `scenes/…` over the home ' +
              'scene pictures, `openings/…` the opening animations, `guides/…` the Apple Health ' +
              'sync guide’s screenshots), in place of the bundled file there.',
            example: 'avatar/art/top/warmup-tee/torso.svg',
          }),
          sha256: z
            .string()
            .meta({ description: 'The file’s SHA-256, lowercase hex; also its name.' }),
          size: z.int().min(1).meta({ description: 'Its size in bytes.' }),
          rigVersion: z.int().min(1).meta({
            description:
              'The lowest rig version that draws it: a build with an older rig leaves it out.',
          }),
        }),
      )
      .meta({
        description: 'Every file put over the bundled art. Paths not listed use the bundled file.',
      }),
  })
  .openapi('ArtCatalog');

/** The `art` section: the art files apps download over the ones they bundle. */
export function artSection(art: Art): CatalogSection<typeof ArtCatalog> {
  return {
    name: 'art',
    schema: ArtCatalog,
    load: async () => {
      const { generation, baseUrl, files } = await art.manifest();
      return { generation, baseUrl: baseUrl.href, files: files.map((file) => ({ ...file })) };
    },
  };
}

const Color = z.string().meta({ description: '`#RRGGBB`.', example: '#16384D' });

export const ScenesCatalog = z
  .looseObject({
    scenes: z
      .array(
        z.looseObject({
          id: z
            .string()
            .meta({ description: 'The id squads’ picks and 战报 name.', example: 'ski' }),
          names: Names,
          colors: z
            .looseObject({
              signature: Color.meta({
                description: 'The 打卡 button, the week’s icons, the poster.',
              }),
              onSignature: Color.meta({ description: 'Text drawn on the signature.' }),
              wash: Color.meta({ description: 'Its light ground.' }),
              text: Color.meta({ description: 'Its text colour on light grounds.' }),
              floor: Color,
            })
            .openapi('SceneColors'),
          limited: z.boolean().meta({
            description:
              'True for a scene open only part of the year (冬季限定). The picker offers it ' +
              'while `GET /squads/{squadId}/scene` lists it.',
          }),
          switchId: z
            .string()
            .optional()
            .meta({
              description:
                'The switch a limited scene follows (the `switches` section): it is open only ' +
                'while that switch is on.',
              example: 'winter',
            }),
        }),
      )
      .meta({
        description:
          'Every scene the picker may offer, in its order; retired ones are left out. The app ' +
          'draws the gym for one it has no art for.',
      }),
  })
  .openapi('ScenesCatalog');

/** The `scenes` section: each scene's names and colours, so a new colour needs no release. */
export function scenesSection(scenes: Pick<Scenes, 'list'>): CatalogSection<typeof ScenesCatalog> {
  return {
    name: 'scenes',
    schema: ScenesCatalog,
    load: async () => ({
      scenes: (await scenes.list())
        .filter(({ offered }) => offered)
        .map(({ id, names, colors, switchId }) => ({
          id,
          names: { ...names },
          colors: { ...colors },
          limited: switchId !== undefined,
          ...(switchId === undefined ? {} : { switchId }),
        })),
    }),
  };
}

export const SwitchesCatalog = z
  .looseObject({
    switches: z
      .array(
        z.looseObject({
          id: z.string().meta({ example: 'winter' }),
          mode: z.string().meta({
            description: '`on`, `off` or `schedule` (on only in `window`); read any other as off.',
            example: 'schedule',
          }),
          window: z
            .looseObject({
              start: z.string().meta({ description: '`MM-DD`, included.', example: '11-15' }),
              end: z.string().meta({ description: '`MM-DD`, included.', example: '03-31' }),
            })
            .optional()
            .meta({
              description:
                'A scheduled switch’s days every year, New York time; it may run over New ' +
                'Year. The app never shows them.',
            })
            .openapi('SwitchWindow'),
        }),
      )
      .meta({ description: 'Every global switch scenes, stores and pieces follow.' }),
  })
  .openapi('SwitchesCatalog');

/** The `switches` section: each switch's mode and days, so the app works out what is on itself. */
export function switchesSection(
  switches: Pick<Switches, 'list'>,
): CatalogSection<typeof SwitchesCatalog> {
  return {
    name: 'switches',
    schema: SwitchesCatalog,
    load: async () => ({
      switches: (await switches.list()).map(({ id, mode, window }) => ({
        id,
        // A switch in preview is on only for previewers, on their own unlocks and squad scene: off here.
        mode: mode === 'preview' ? 'off' : mode,
        ...(window === undefined ? {} : { window: { ...window } }),
      })),
    }),
  };
}

export const AppBuildCatalog = z
  .looseObject({
    minimumBuild: z
      .string()
      .optional()
      .meta({
        description:
          'The lowest build (CFBundleVersion, such as `190` or `190.1`) that may run, compared ' +
          'number by number; an older app shows only 有新版本 and a button to the App Store. ' +
          'Left out while every build may run.',
        example: '190',
      }),
  })
  .openapi('AppBuildCatalog');

/** The `appBuild` section: the lowest build of the app that may still run. */
export function appBuildSection(
  minimum: Pick<MinimumBuilds, 'current'>,
): CatalogSection<typeof AppBuildCatalog> {
  return {
    name: 'appBuild',
    schema: AppBuildCatalog,
    load: async () => {
      const { build } = await minimum.current();
      return build === null ? {} : { minimumBuild: build };
    },
  };
}

export const ReactionsCatalog = z
  .looseObject({
    quick: z.array(z.string()).meta({
      description:
        'The emoji the reaction bar offers first, in order. Any one emoji is still a reaction.',
      example: ['❤️', '💪', '😂', '🤤', '😮', '😡'],
    }),
  })
  .openapi('ReactionsCatalog');

/** The `reactions` section: the reaction bar's quick emoji. */
export function reactionsSection(
  reactions: Pick<QuickReactionsAdmin, 'current'>,
): CatalogSection<typeof ReactionsCatalog> {
  return {
    name: 'reactions',
    schema: ReactionsCatalog,
    load: async () => ({ quick: [...(await reactions.current()).emoji] }),
  };
}

const switchRef = (what: string) =>
  z
    .string()
    .optional()
    .meta({
      description: `The switch ${what} is out with (the \`switches\` section); none for always.`,
      example: 'winter',
    });

export const StoresCatalog = z
  .looseObject({
    stores: z
      .array(
        z.looseObject({
          id: z.string().meta({ example: 'powder' }),
          switchId: switchRef('the store'),
          free: z.boolean().meta({
            description:
              'Open to everyone with no 训练 (no unlock rule), such as WARM-UP; any other store ' +
              'is earned.',
          }),
        }),
      )
      .meta({
        description:
          'Every store on the 商店街, in its order; retired ones are left out. A signed-in ' +
          'member’s own street comes from `GET /me/unlocks`; the app has art only for some.',
      }),
  })
  .openapi('StoresCatalog');

/** The `stores` section: the 商店街's stores, the switch each one is open with and the free ones. */
export function storesSection(
  unlocks: Pick<UnlocksAdmin, 'stores' | 'rules'>,
): CatalogSection<typeof StoresCatalog> {
  return {
    name: 'stores',
    schema: StoresCatalog,
    load: async () => {
      const [stores, rules] = await Promise.all([unlocks.stores(), unlocks.rules()]);
      const earned = new Set(rules.filter(({ kind }) => kind === 'store').map(({ id }) => id));
      return {
        stores: stores
          .filter(({ offered }) => offered)
          .map(({ id, switchId }) => ({
            id,
            ...(switchId === undefined ? {} : { switchId }),
            free: !earned.has(id),
          })),
      };
    },
  };
}

export const PiecesCatalog = z
  .looseObject({
    pieces: z
      .array(
        z.looseObject({
          id: z.string().meta({ example: 'powder-salmon' }),
          storeId: z.string().meta({ example: 'powder' }),
          slot: z
            .string()
            .meta({ description: 'Where it is worn: top, bottom, shoes, hat or acc.' }),
          starter: z.boolean().meta({
            description: 'Everyone has it while it is out; any other piece is earned by a rule.',
          }),
          switchId: switchRef('the piece, apart from its store,'),
        }),
      )
      .meta({
        description:
          'Every clothing piece in a store; retired ones, and a retired store’s, are left out.',
      }),
  })
  .openapi('PiecesCatalog');

/** The `pieces` section: each piece's store, slot, whether it is a starter and its own switch. */
export function piecesSection(
  unlocks: Pick<UnlocksAdmin, 'stores' | 'pieces'>,
): CatalogSection<typeof PiecesCatalog> {
  return {
    name: 'pieces',
    schema: PiecesCatalog,
    load: async () => {
      const [stores, pieces] = await Promise.all([unlocks.stores(), unlocks.pieces()]);
      const offered = new Set(stores.filter((store) => store.offered).map(({ id }) => id));
      return {
        pieces: pieces
          .filter((piece) => piece.offered && offered.has(piece.storeId))
          .map(({ id, storeId, slot, starter, switchId }) => ({
            id,
            storeId,
            slot,
            starter,
            ...(switchId === undefined ? {} : { switchId }),
          })),
      };
    },
  };
}

/**
 * The catalog's body: its version, then each section under its name. Every object in it is
 * loose, unlike the other bodies, so a section, list or field added later still reads in the
 * builds already out: the catalog is how the app changes without a release. Every section is
 * optional in the contract, though this server sends them all, so a build that reaches a server
 * from before a section was added keeps its own copy of that section and reads the rest.
 */
export function catalogBody(sections: readonly CatalogSection[]) {
  return z
    .looseObject({
      version: bodyVersion(1),
      ...Object.fromEntries(sections.map(({ name, schema }) => [name, schema.optional()])),
    })
    .openapi('Catalog');
}

/** How long the server keeps the catalog before reading the database again. */
const FRESH_MS = 60_000;

/**
 * `GET /public/catalog`: the data the app shows that lives in the database, such as the sports
 * list. Public, since sign-up shows it before there is a session, and nothing in it is private.
 * The server keeps it for a minute, so an edit to the database shows within about one.
 */
export function catalog(deps: {
  readonly sections: readonly CatalogSection[];
  readonly publicRoutes: PublicRoutes;
  readonly clock: () => Date;
}) {
  const Body = catalogBody(deps.sections);

  let kept:
    { readonly at: number; readonly loading: Promise<{ json: string; etag: string }> } | undefined;
  /** The catalog as JSON and its ETag, read again once it is a minute old. */
  function current() {
    const now = deps.clock().getTime();
    if (kept === undefined || now - kept.at >= FRESH_MS) {
      const loading = load();
      kept = { at: now, loading };
      // A failed read isn't kept: the next request tries again.
      loading.catch(() => {
        if (kept?.loading === loading) kept = undefined;
      });
    }
    return kept.loading;
  }
  async function load() {
    const loaded = await Promise.all(
      deps.sections.map(async ({ name, load }) => [name, await load()] as const),
    );
    const json = JSON.stringify(Body.parse({ version: 1, ...Object.fromEntries(loaded) }));
    const etag = `"${createHash('sha256').update(json).digest('base64url').slice(0, 27)}"`;
    return { json, etag };
  }

  const route = createRoute({
    method: 'get',
    path: '/public/catalog',
    operationId: 'getCatalog',
    summary: 'The lists the app shows, such as every sport',
    description:
      'No sign-in. Send the last `ETag` as `If-None-Match` to get 304 while it is unchanged. ' +
      'An edit shows within about a minute. Limited per client address.',
    middleware: [rateLimited(deps.publicRoutes.catalogReads, deps.publicRoutes.proxyHops)] as const,
    request: {
      headers: z.object({
        'if-none-match': z
          .string()
          .optional()
          .meta({ description: 'The `ETag` of the catalog the app has.' }),
      }),
    },
    responses: {
      200: {
        description: 'The catalog',
        headers: {
          ETag: { description: 'Names this version of the catalog.', schema: { type: 'string' } },
          'Cache-Control': {
            description: '`no-cache`: keep it, but ask again before using it as current.',
            schema: { type: 'string' },
          },
        },
        content: { 'application/json': { schema: Body } },
      },
      304: { description: 'Unchanged since the `If-None-Match` version' },
      429: {
        ...problem('Too many reads from this address (`REQUESTS_TOO_FREQUENT`)'),
        headers: {
          'Retry-After': {
            description: 'Seconds until reads from this address are taken again.',
            schema: { type: 'integer' },
          },
        },
      },
    },
  });

  return new OpenAPIHono().openapi(route, async (c) => {
    const { json, etag } = await current();
    const headers = { etag, 'cache-control': 'no-cache' };
    const known = c.req
      .valid('header')
      ['if-none-match']?.split(',')
      .map((tag) => tag.trim());
    if (known?.includes(etag) === true) return c.body(null, 304, headers);
    return c.body(json, 200, { ...headers, 'content-type': 'application/json' });
  });
}
