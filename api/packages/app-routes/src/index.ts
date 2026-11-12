import { z } from 'zod';

// @wildcard/app-routes: every place in the app a link may open, by its address (Tracy,
// 2026-11-12: where a button goes is data, never a release). An address is a bare path such as
// `store/powder` (the app also opens it as `wildcard://store/powder`); the app opens it with one router
// (`AppDestination(address:)`), and a build that doesn't know one shows no button. Adding a page
// to the app adds its route here and in the app's router, once; from then on any notice, card or
// push may open it. `routes.json` beside this package is its copy for the app's tests
// (`pnpm --dir api app-routes` rewrites it; a test fails while it is stale).

/** One route: its pattern, what it opens, and an address the app's test reads. */
export interface AppRoute {
  /** The address, with `<…>` for its part that varies, such as `store/<storeId>`. */
  readonly pattern: string;
  /** What it opens, for whoever writes a button. */
  readonly opens: string;
  /** A whole address of it, which every build that knows it reads. */
  readonly sample: string;
  /** What the varying part may be, as a regular expression's source, if it has one. */
  readonly id?: string;
}

/** Every route, in the order an admin reads them. */
export const APP_ROUTES: readonly AppRoute[] = [
  { pattern: 'today', opens: '今天', sample: 'today' },
  { pattern: 'check-in', opens: '今天, with the check-in kinds open (打卡)', sample: 'check-in' },
  { pattern: 'coach', opens: 'the squad coach’s own page (its cards), over 今天', sample: 'coach' },
  { pattern: 'squad', opens: '小队', sample: 'squad' },
  { pattern: 'coaches', opens: '教练招聘会', sample: 'coaches' },
  {
    pattern: 'recap/<weekStart>',
    opens: 'the squad’s 战报 for the week starting that Monday',
    sample: 'recap/2026-11-02',
    id: '^\\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\\d|3[01])$',
  },
  { pattern: 'feed', opens: '动态', sample: 'feed' },
  {
    pattern: 'post/<checkInId>',
    opens: 'one post’s own page',
    sample: 'post/7b0c1f4e-2d3a-4b5c-8d9e-0f1a2b3c4d5e',
    id: '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  },
  { pattern: 'notices', opens: '通知, behind the bell on 动态', sample: 'notices' },
  { pattern: 'me', opens: '我', sample: 'me' },
  {
    pattern: 'badges',
    opens: '我’s player card turned to its badge board (徽章)',
    sample: 'badges',
  },
  { pattern: 'schedule', opens: '出赛表', sample: 'schedule' },
  { pattern: 'my-posts', opens: '我的动态, the member’s own posts', sample: 'my-posts' },
  { pattern: 'settings', opens: '我’s 设置', sample: 'settings' },
  { pattern: 'feedback', opens: '意见反馈', sample: 'feedback' },
  { pattern: 'stores', opens: '商店街', sample: 'stores' },
  {
    pattern: 'store/<storeId>',
    opens: 'one store on 商店街',
    sample: 'store/powder',
    id: '^[a-z][A-Za-z0-9]{0,39}$',
  },
  { pattern: 'wardrobe', opens: '衣橱 in the character editor', sample: 'wardrobe' },
  {
    pattern: 'wardrobe/<pieceId>',
    opens: '衣橱, trying that piece on',
    sample: 'wardrobe/lap-bib',
    id: '^[a-z][a-z0-9-]{0,47}$',
  },
];

const idPatterns = new Map(
  APP_ROUTES.flatMap((route) =>
    route.id === undefined ? [] : [[route.pattern, new RegExp(route.id, 'u')] as const],
  ),
);

/** The scheme of a link into the app. */
export const APP_SCHEME = 'wildcard';

/**
 * The route `address` is on; undefined for none. Addresses are kept bare (`store/powder`), so
 * builds from before links read them too; the app also opens one as `wildcard://<address>`.
 */
export function routeOf(address: string): AppRoute | undefined {
  const [word = '', id, ...rest] = address.split('/');
  if (rest.length > 0) return undefined;
  return APP_ROUTES.find((route) => {
    const [routeWord, routeId] = route.pattern.split('/');
    if (routeWord !== word) return false;
    if (routeId === undefined) return id === undefined;
    return id !== undefined && idPatterns.get(route.pattern)?.test(id) === true;
  });
}

/** `routes.json`, the routes as the app's tests read them. */
export function routesJson(): string {
  return `${JSON.stringify({ version: 1, routes: APP_ROUTES }, null, 2)}\n`;
}

/**
 * A place in the app: an address on one of the routes, such as `store/powder`, `post/<id>` or
 * `coach`, written bare. A build that doesn't know it shows no button, so a route added later is
 * safe to send to older builds.
 */
export const AppAddress = z
  .string()
  .max(200)
  .refine((address) => routeOf(address) !== undefined, {
    message: 'not a place in the app (list_app_routes lists them)',
  });
export type AppAddress = z.infer<typeof AppAddress>;
