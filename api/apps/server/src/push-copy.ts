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
  'push.weeklyAwards.ready': [],
  'push.weeklyAwards.stuck': ['squad', 'failures', 'lastError'],
} as const satisfies Record<string, readonly string[]>;

export type PushCopyKey = keyof typeof PUSH_COPY;

/** One text per name in `Names`, as a tuple of the same length. */
type Values<Names extends readonly string[]> = { readonly [Index in keyof Names]: string };

/** A push's alert: a key from `PUSH_COPY` and one value for each of its placeholders, if any. */
export function pushAlert<Key extends PushCopyKey>(
  key: Key,
  args: Values<(typeof PUSH_COPY)[Key]>,
): { readonly key: Key; readonly args?: readonly string[] } {
  return args.length === 0 ? { key } : { key, args };
}
