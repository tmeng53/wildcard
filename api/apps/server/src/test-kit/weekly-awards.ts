// Tests only. The weekly awards for an app whose test never reads them.
const unused = () => Promise.reject(new Error('unused'));

export const unusedWeeklyAwards = {
  awards: { give: unused, find: unused, claimWinners: unused, forget: unused },
  clock: () => new Date(),
};
