import type { Hidden, Moderation } from '@wildcard/moderation';

/** Moderation for flows tested without a database: nobody blocked, nothing reported. */
export const nothingHidden: Pick<Moderation, 'hiddenFor' | 'blockedAmong'> = {
  hiddenFor: (): Promise<Hidden> =>
    Promise.resolve({
      members: new Set(),
      checkIns: new Set(),
      comments: new Set(),
      coachReplies: new Set(),
      coachAnswers: new Set(),
    }),
  blockedAmong: () => Promise.resolve(new Set<string>()),
};
