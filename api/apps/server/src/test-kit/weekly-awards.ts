// Tests only. The weekly awards for an app whose test never reads them.
import type { MemberId, ShownBoardTitle, WeeklyAwards } from '@wildcard/weekly-awards';

const unused = () => Promise.reject(new Error('unused'));

export const unusedWeeklyAwards = {
  awards: {
    give: unused,
    find: unused,
    claimNudge: unused,
    claimReadyPush: unused,
    titlesWon: unused,
    story: unused,
    freezeStory: unused,
    storyWeeks: unused,
    storiesWaiting: unused,
    // The squad's today reads boards: nobody has won anything.
    boards: (members: readonly MemberId[]) =>
      Promise.resolve(
        new Map(members.map((member): [MemberId, readonly ShownBoardTitle[]] => [member, []])),
      ),
  } satisfies WeeklyAwards,
  clock: () => new Date(),
};

/** The Sunday summary's words, for an app whose test never reads them. */
export const unusedWeekSummaryWords = unused;

/** Each squad's coach, for an app whose test never reads it. */
export const unusedCoachHiring = {
  hire: unused,
  fire: unused,
  change: unused,
  current: unused,
  offered: unused,
};

/** Coaches' letters to the next one, for an app whose test never writes one. */
export const unusedCoachLetters = { write: unused };

/** What coaches said, for an app whose test never reads it. */
export const unusedCoachActivity = {
  squad: unused,
  putAway: unused,
  answerChallenge: unused,
  challenge: unused,
  completeChallenge: unused,
  cards: unused,
  markSeen: unused,
  spoke: unused,
};

/** What members unlocked, for an app whose test never reads it. */
export const unusedUnlocks = {
  of: unused,
  standing: unused,
  claimsOf: unused,
  claim: unused,
  // Every profile save keeps what the look wears; a test without unlocks has nothing to keep.
  keepWorn: () => Promise.resolve(),
};

/** What coaches gave members, for an app whose test never reads it. */
export const unusedGifts = { of: unused, open: unused };

/**
 * What members were told, and their live events, for an app whose test never reads them: notices
 * told are dropped, since keeping them never decides what a request answers.
 */
export const ignoredNotices = {
  notices: { tell: () => Promise.resolve(), page: unused, markSeen: unused },
  coachNames: unused,
  liveEvents: { subscribe: unused, close: () => Promise.resolve() },
};
