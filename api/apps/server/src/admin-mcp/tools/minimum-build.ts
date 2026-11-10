import { AdminId, BuildNumber, type MinimumBuilds } from '@wildcard/switches';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The lowest build of the app that may run. An older app shows only 有新版本 and a button to the
// App Store, so a broken build or one the API can no longer serve is sent to update, with no
// release. The public catalog serves it; apps see a change within a minute of their next read.

interface MinimumBuildToolDependencies {
  readonly minimum: MinimumBuilds;
}

/** `get_minimum_build`: the lowest build that may run now. */
export function getMinimumBuild({ minimum }: MinimumBuildToolDependencies) {
  return adminTool({
    name: 'get_minimum_build',
    title: 'Read the minimum app build',
    description:
      'Shows the lowest app build (CFBundleVersion, the TestFlight build number such as 190.1) ' +
      'that may still run; null when every build may.',
    changes: false,
    input: z.strictObject({}),
    run: async () => minimum.current(),
  });
}

/** `set_minimum_build`: sets the lowest build that may run. */
export function setMinimumBuild({ minimum }: MinimumBuildToolDependencies) {
  return adminTool({
    name: 'set_minimum_build',
    title: 'Set the minimum app build',
    description:
      'Sets the lowest app build that may run, compared number by number (190 lets 190 and 190.1 ' +
      'run, stops 189.9). An older app shows only 有新版本 and a button to the App Store until ' +
      'it is updated, so set it only to a build the App Store already offers. null lets every ' +
      'build run again. Builds from before this setting existed never read it. Returns it now.',
    changes: true,
    input: z.strictObject({ build: BuildNumber.nullable() }),
    run: async ({ build }, { admin }) => minimum.set(build, AdminId.parse(admin)),
  });
}

export const minimumBuildTools = (deps: MinimumBuildToolDependencies) => [
  getMinimumBuild(deps),
  setMinimumBuild(deps),
];
