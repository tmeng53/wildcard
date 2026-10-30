import { createHash } from 'node:crypto';

import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import type { SportCatalog, Sports } from '@wildcard/sports';

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
          sports: z.array(
            z.looseObject({
              id: z.string().meta({
                description:
                  'What a 练了 or a planned day sends as `sport`. Never changes, and a sport is ' +
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
        checkInQuick: sportIds('A 练了’s quick picks, before the whole list.'),
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
  categories: catalog.categories.map(({ id, names, sports }) => ({
    id,
    names: { ...names },
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

/**
 * The catalog's body: its version, then each section under its name. Every object in it is
 * loose, unlike the other bodies, so a section, list or field added later still reads in the
 * builds already out: the catalog is how the app changes without a release.
 */
export function catalogBody(sections: readonly CatalogSection[]) {
  return z
    .looseObject({
      version: bodyVersion(1),
      ...Object.fromEntries(sections.map(({ name, schema }) => [name, schema])),
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
