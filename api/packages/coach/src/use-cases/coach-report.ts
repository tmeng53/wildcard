import type { SquadId } from '../domain/settings.js';
import type { CoachReportStore, CoachUsage, SquadCoaching } from '../ports.js';

/** What a squad's coach has done and spent, for the admins. */
export interface CoachReport {
  squad(squad: SquadId, now: Date): Promise<SquadCoaching>;
}

export function createCoachReport(deps: {
  readonly store: CoachReportStore;
  readonly usage: Pick<CoachUsage, 'total'>;
}): CoachReport {
  return {
    async squad(squad, now) {
      const weekAgo = new Date(now.getTime() - 7 * 86_400_000);
      return {
        ...(await deps.store.squad(squad)),
        usage: {
          total: await deps.usage.total({ squad }),
          lastWeek: await deps.usage.total({ squad, since: weekAgo }),
        },
      };
    },
  };
}
