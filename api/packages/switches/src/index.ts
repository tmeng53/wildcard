// @wildcard/switches: global, scheduled on/off switches that limited scenes, stores, pieces and
// anything later follow, kept in the database so a theme turns on or off without a release;
// and the lowest build of the app that may still run.

export { createPostgresMinimumBuild } from './adapters/postgres-minimum-build.js';
export { createPostgresSwitchStore, type SwitchTables } from './adapters/postgres-switch-store.js';
export {
  CoachNote,
  coachNotesOn,
  DayOffset,
  inWindow,
  isOn,
  isOnForPreviewer,
  PLAIN_VIEW,
  MonthDay,
  SWITCH_MODES,
  SwitchEdit,
  SwitchId,
  SwitchMode,
  type Switch,
  type SwitchSetting,
  type SwitchView,
  type SwitchWindow,
  wasOn,
} from './domain/switches.js';
export { AdminId, BuildNumber, MinimumBuild } from './domain/minimum-build.js';
export type { MinimumBuildStore, SwitchStore } from './ports.js';
export { createMinimumBuilds, type MinimumBuilds } from './use-cases/minimum-build.js';
export {
  createSwitches,
  type MemberSwitches,
  type SwitchOn,
  type SwitchWasOn,
  type Switches,
  type SwitchesAdmin,
} from './use-cases/switches.js';
