const newYorkDays = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });

/** `at`'s day in New York, `YYYY-MM-DD`: the day global switches and their windows go by. */
export function newYorkDay(at: Date): string {
  return newYorkDays.format(at);
}
