// Tests only. The weekly awards for an app whose test never reads them.
const unused = () => Promise.reject(new Error('unused'));

export const unusedWeeklyAwards = {
  awards: {
    give: unused,
    find: unused,
    claimNudge: unused,
    claimWinners: unused,
    titlesWon: unused,
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
