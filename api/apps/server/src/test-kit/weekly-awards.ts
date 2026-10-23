// Tests only. The weekly awards for an app whose test never reads them.
const unused = () => Promise.reject(new Error('unused'));

export const unusedWeeklyAwards = {
  awards: { give: unused, find: unused, claimNudge: unused, claimWinners: unused },
  clock: () => new Date(),
};
