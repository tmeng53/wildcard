import {
  MemberId as CheckInMember,
  type CheckIns,
  type SquadId,
  type SquadToday,
} from '@wildcard/check-ins';
import { MemberId as ProfileMember, type Members } from '@wildcard/members';

/** The most of today's check-ins the push carries; the app's push view shows them all. */
export const TODAY_POSTS = 4;
/** The most reactions a post carries, newest first, besides the member's own. */
export const POST_REACTIONS = 8;
/**
 * A post's words are cut to this many characters as people see them, and to `POST_TEXT_BYTES`,
 * with `…`; a custom sport and a nickname to their own bytes. Emoji take up to 25 bytes each, so
 * the bytes bound what the characters can't.
 */
export const POST_TEXT = 40;
export const POST_TEXT_BYTES = 160;
export const SPORT_BYTES = 60;
export const NAME_BYTES = 48;
/** The most patters the push names in its view's header. */
export const POKERS = 3;
/**
 * The most bytes `today` may take as JSON. APNs takes 4KB in all; at their fullest (8 members, every
 * name, sport and caption at its byte cut, the widest emoji everywhere) the alert and the rest of
 * the event take under 700 bytes and `today` about 3.3KB. A safety net: posts are dropped from
 * the end (and counted in `more`) until it fits.
 */
export const TODAY_BYTES = 3400;

/**
 * Today's check-ins in the daily push, for the push's long-press view on the phone, which must
 * show them without loading anything (Apple asks a notification's view not to). Teammates'
 * posts only, newest first; members are listed once and posts point at them by index.
 */
// Types, not interfaces: an interface doesn't fit the push event's JSON index signature.
// eslint-disable-next-line @typescript-eslint/consistent-type-definitions
export type PushToday = {
  /** Everyone the posts name; the first is the member the push is for. No name before they make their character. */
  readonly members: readonly { readonly id: string; readonly name?: string }[];
  readonly posts: readonly PushPost[];
  /** Teammates' posts today beyond those in `posts`. */
  readonly more: number;
  /** Who patted the member since their last push (indices in `members`), at most `POKERS`. */
  readonly pokedBy?: readonly number[];
};

// eslint-disable-next-line @typescript-eslint/consistent-type-definitions
export type PushPost = {
  readonly id: string;
  /** Index in `members`. */
  readonly by: number;
  readonly kind: 'trained' | 'healthyMeal' | 'cheatMeal' | 'disclaimer';
  readonly sport?: string;
  readonly customSport?: string;
  readonly at: string;
  /** The caption, or the 请假条's text, cut to `POST_TEXT` and `POST_TEXT_BYTES`. */
  readonly text?: string;
  /** `[member index, emoji]`, newest first: the newest `POST_REACTIONS`, and the member's own always. */
  readonly reactions: readonly (readonly [number, string])[];
  /** All the post's reactions, for 「+n」. */
  readonly reactionCount: number;
};

const graphemes = new Intl.Segmenter('und', { granularity: 'grapheme' });

/** `text` cut to `characters` graphemes and `bytes` bytes of UTF-8, ending in `…` when cut. */
function cut(
  text: string,
  { characters = Infinity, bytes }: { readonly characters?: number; readonly bytes: number },
): string {
  const all = Array.from(graphemes.segment(text), ({ segment }) => segment);
  if (all.length <= characters && Buffer.byteLength(text) <= bytes) return text;
  // Room for the `…`, 3 bytes.
  let kept = '';
  for (const segment of all.slice(0, characters - 1)) {
    if (Buffer.byteLength(kept + segment) > bytes - 3) break;
    kept += segment;
  }
  return `${kept}…`;
}

/** What the daily push carries of `viewer`'s squad's day, from the squad's today. */
export async function pushToday(
  deps: {
    readonly checkIns: Pick<CheckIns, 'listForSquad'>;
    readonly members: Pick<Members, 'squadmates'>;
  },
  {
    viewer,
    squad,
    today,
    pokers,
  }: {
    readonly viewer: string;
    readonly squad: SquadId;
    readonly today: SquadToday;
    /** Who patted the member, first first. */
    readonly pokers: readonly string[];
  },
): Promise<PushToday> {
  // Each teammate's own today, in their time zone.
  const dayOf = new Map<string, string>(today.members.map(({ member, day }) => [member, day]));
  const days = [...dayOf.values()].sort();
  const [from, to] = [days[0], days.at(-1)];
  const listed =
    from === undefined || to === undefined
      ? []
      : await deps.checkIns.listForSquad({
          viewer: CheckInMember.parse(viewer),
          squad,
          days: { from, to },
        });
  const posts = listed
    .filter(({ checkIn }) => checkIn.member !== viewer && dayOf.get(checkIn.member) === checkIn.day)
    .sort((a, b) => b.checkIn.createdAt.getTime() - a.checkIn.createdAt.getTime());

  const ids = [viewer];
  const index = (member: string) => {
    const at = ids.indexOf(member);
    if (at >= 0) return at;
    ids.push(member);
    return ids.length - 1;
  };
  const patted = pokers
    .filter((each) => each !== viewer)
    .slice(0, POKERS)
    .map(index);
  const shown = posts.map(({ checkIn, reactions }): PushPost => {
    const newest = [...reactions].sort((a, b) => b.reactedAt.getTime() - a.reactedAt.getTime());
    const kept = newest.filter((each, at) => at < POST_REACTIONS || each.member === viewer);
    const words =
      checkIn.kind === 'trained'
        ? checkIn.training.caption
        : checkIn.kind === 'disclaimer'
          ? checkIn.disclaimer.text
          : checkIn.meal.caption;
    return {
      id: checkIn.id,
      by: index(checkIn.member),
      kind: checkIn.kind,
      ...(checkIn.kind === 'trained'
        ? {
            sport: checkIn.training.sport,
            ...(checkIn.training.customSport === undefined
              ? {}
              : { customSport: cut(checkIn.training.customSport, { bytes: SPORT_BYTES }) }),
          }
        : {}),
      at: checkIn.createdAt.toISOString(),
      ...(words === undefined
        ? {}
        : { text: cut(words, { characters: POST_TEXT, bytes: POST_TEXT_BYTES }) }),
      reactions: kept.map(({ member, emoji }) => [index(member), emoji] as const),
      reactionCount: reactions.length,
    };
  });

  let carried = shown.slice(0, TODAY_POSTS);
  const profiles = await deps.members.squadmates(ids.map((id) => ProfileMember.parse(id)));
  const build = (): PushToday => {
    // Only the members the carried posts name, renumbered.
    const used = [
      ...new Set([
        0,
        ...patted,
        ...carried.flatMap((post) => [post.by, ...post.reactions.map(([at]) => at)]),
      ]),
    ];
    const renumber = new Map(used.map((old, at) => [old, at]));
    const at = (old: number) => renumber.get(old) ?? 0;
    return {
      members: used.map((old) => {
        const id = ids[old] ?? viewer;
        const name = profiles.get(ProfileMember.parse(id))?.character?.nickname;
        return name === undefined ? { id } : { id, name: cut(name, { bytes: NAME_BYTES }) };
      }),
      posts: carried.map((post) => ({
        ...post,
        by: at(post.by),
        reactions: post.reactions.map(([who, emoji]) => [at(who), emoji] as const),
      })),
      more: posts.length - carried.length,
      ...(patted.length === 0 ? {} : { pokedBy: patted.map(at) }),
    };
  };
  let built = build();
  while (carried.length > 0 && Buffer.byteLength(JSON.stringify(built)) > TODAY_BYTES) {
    carried = carried.slice(0, -1);
    built = build();
  }
  return built;
}
