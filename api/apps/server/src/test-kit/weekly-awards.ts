// Tests only. The weekly awards for an app whose test never reads them.
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
    storiesWaiting: unused,
  },
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

/** What coaches said, for an app whose test never reads it. */
export const unusedCoachActivity = { squad: unused, spoke: unused };

/** What members unlocked, for an app whose test never reads it. */
export const unusedUnlocks = { of: unused };

/**
 * What members were told, and their live events, for an app whose test never reads them: notices
 * told are dropped, since keeping them never decides what a request answers.
 */
export const ignoredNotices = {
  notices: { tell: () => Promise.resolve(), page: unused, markSeen: unused },
  coachNames: unused,
  liveEvents: { subscribe: unused, close: () => Promise.resolve() },
};
