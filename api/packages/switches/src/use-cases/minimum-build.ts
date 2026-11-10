import { MinimumBuild, type BuildNumber } from '../domain/minimum-build.js';
import type { MinimumBuildStore } from '../ports.js';

/** The lowest build of the app that may run, for the catalog to send and admins to change. */
export interface MinimumBuilds {
  current(): Promise<MinimumBuild>;
  /** Sets it (null lets every build run), logged as `by`'s change. Returns it now. */
  set(build: BuildNumber | null, by: string): Promise<MinimumBuild>;
}

export function createMinimumBuilds({
  store,
}: {
  readonly store: MinimumBuildStore;
}): MinimumBuilds {
  return {
    current: () => store.current(),
    set: async (build, by) => {
      const minimum = MinimumBuild.parse({ version: 1, build });
      await store.save(minimum, by);
      return minimum;
    },
  };
}
