/**
 * Every push alert the server sends, by its key in the app's String Catalog
 * (`ios/Wildcard/Localizable.xcstrings`), with what fills each of its `%n$@` placeholders, in
 * order. The words live in the app; `push-copy.test.ts` checks that each key here has Chinese and
 * English there with exactly these placeholders, and that the app has no push copy left over.
 */
export const PUSH_COPY = {
  'push.dailyProgress': ['trainedDays', 'plannedDays'],
  'push.dailyProgress.received': ['trainedDays', 'plannedDays', 'teammates'],
  'push.dailyProgress.poke': ['trainedDays', 'plannedDays', 'poker'],
  'push.dailyProgress.poke.more': ['trainedDays', 'plannedDays', 'poker', 'otherPokers'],
  'push.teammate.trained': ['teammate', 'sport'],
  'push.teammate.trained.minutes': ['teammate', 'sport', 'minutes'],
  'push.comment': ['commenter', 'text'],
  'push.comment.reply': ['commenter', 'text'],
  'push.coach.note': ['coach', 'text'],
  'push.comment.mention': ['commenter', 'text'],
  'push.trainedWith': ['teammate'],
  'push.weeklyAwards.ready': [],
  'push.weeklyAwards.stuck': ['squad', 'failures', 'lastError'],
} as const satisfies Record<string, readonly string[]>;

export type PushCopyKey = keyof typeof PUSH_COPY;

/**
 * Values a push still sends that its words no longer show. The coach's note stays off the lock
 * screen (Tracy, 2026-11-07: 「毛头给你发了一条消息」, the note itself only in the app), but builds
 * from before that change fill `%2$@` with it, and iOS can't fill a placeholder it isn't sent,
 * so it goes until no such build is installed.
 */
export const UNSHOWN_ARGS: Partial<Record<PushCopyKey, readonly string[]>> = {
  'push.coach.note': ['text'],
};

/** One text per name in `Names`, as a tuple of the same length. */
type Values<Names extends readonly string[]> = { readonly [Index in keyof Names]: string };

/** A push's alert: a key from `PUSH_COPY` and one value for each of its placeholders, if any. */
export function pushAlert<Key extends PushCopyKey>(
  key: Key,
  args: Values<(typeof PUSH_COPY)[Key]>,
): { readonly key: Key; readonly args?: readonly string[] } {
  return args.length === 0 ? { key } : { key, args };
}
