// @wildcard/switches: global, scheduled on/off switches that limited scenes, stores, pieces and
// anything later follow, kept in the database so a theme turns on or off without a release.

export { createPostgresSwitchStore, type SwitchTables } from './adapters/postgres-switch-store.js';
export {
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
export type { SwitchStore } from './ports.js';
export {
  createSwitches,
  type MemberSwitches,
  type SwitchOn,
  type SwitchWasOn,
  type Switches,
  type SwitchesAdmin,
} from './use-cases/switches.js';
