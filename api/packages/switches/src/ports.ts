import type { Switch } from './domain/switches.js';

/** Where the switches are kept. */
export interface SwitchStore {
  /** Every switch, by id. */
  list(): Promise<Switch[]>;
  /** Adds or replaces `of`. */
  put(of: Switch): Promise<void>;
}
