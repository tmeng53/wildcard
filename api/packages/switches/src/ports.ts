import type { Switch, SwitchSetting } from './domain/switches.js';

/** Where the switches are kept. */
export interface SwitchStore {
  /** Every switch, by id. */
  list(): Promise<Switch[]>;
  /** Every change to every switch, from its log, the oldest first. */
  history(): Promise<SwitchSetting[]>;
  /** Adds or replaces `of`. */
  put(of: Switch): Promise<void>;
}
