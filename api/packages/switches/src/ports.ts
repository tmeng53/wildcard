import type { Switch, SwitchSetting, SwitchView } from './domain/switches.js';
import type { MinimumBuild } from './domain/minimum-build.js';

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

/** Where the minimum build is kept: one value, and a log of every change to it. */
export interface MinimumBuildStore {
  /** The minimum now. */
  current(): Promise<MinimumBuild>;
  /**
   * Saves `minimum` with `by` as who changed it, unless it is the minimum already: then nothing
   * is saved or logged.
   */
  save(minimum: MinimumBuild, by: string): Promise<void>;
}
