import type { Switch, SwitchSetting, SwitchView } from './domain/switches.js';

/** Where the switches are kept. */
export interface SwitchStore {
  /** Every switch, by id. */
  list(): Promise<Switch[]>;
  /** Every change to every switch, from its log, the oldest first. */
  history(): Promise<SwitchSetting[]>;
  /** Adds or replaces `of`. */
  put(of: Switch): Promise<void>;
  /** How `member` sees the switches now: `PLAIN_VIEW` for anyone never set. */
  viewOf(member: string): Promise<SwitchView>;
  /** Sets how `member` sees the switches, logged with the admin who set it. */
  setView(change: {
    readonly member: string;
    readonly view: SwitchView;
    readonly by: string;
  }): Promise<void>;
  /** Every member who previews switches now, with their day offset. */
  previewers(): Promise<{ readonly member: string; readonly dayOffset: number }[]>;
}
