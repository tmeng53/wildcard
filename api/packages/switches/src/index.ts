// @wildcard/switches: global, scheduled on/off switches that limited scenes, unlock rules and
// anything later follow, kept in the database so a theme turns on or off without a release.

export { createPostgresSwitchStore, type SwitchTables } from './adapters/postgres-switch-store.js';
export {
  inWindow,
  isOn,
  MonthDay,
  SWITCH_MODES,
  SwitchEdit,
  SwitchId,
  SwitchMode,
  type Switch,
  type SwitchWindow,
} from './domain/switches.js';
export type { SwitchStore } from './ports.js';
export {
  createSwitches,
  type SwitchOn,
  type Switches,
  type SwitchesAdmin,
} from './use-cases/switches.js';
