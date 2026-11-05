import { z } from 'zod';

// Switches: one global, scheduled on/off that many things follow at once (a limited scene, a
// store and its pieces, anything later), so a limited theme is a row of data, never a
// concept in code (Tracy, 2026-11-04). Kept in the database (supabase/migrations, `switches`).

/** A switch's id, camelCase, such as `winter`. Never changes. */
export const SwitchId = z.string().regex(/^[a-z][A-Za-z0-9]{0,39}$/);
export type SwitchId = z.infer<typeof SwitchId>;

/** A day of the year, `MM-DD`. */
export const MonthDay = z.string().regex(/^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/);
export type MonthDay = z.infer<typeof MonthDay>;

export const SWITCH_MODES = ['on', 'off', 'schedule'] as const;
export const SwitchMode = z.enum(SWITCH_MODES);
export type SwitchMode = z.infer<typeof SwitchMode>;

/** Days of every year, both included, New York time; the end may come before the start. */
export interface SwitchWindow {
  readonly start: MonthDay;
  readonly end: MonthDay;
}

export interface Switch {
  readonly id: SwitchId;
  /** What it is for, for admins. */
  readonly label: string;
  /** On, off, or on only in `window`. */
  readonly mode: SwitchMode;
  /** Its schedule; always there for one in `schedule` mode. */
  readonly window?: SwitchWindow;
}

/** Whether `day` (`YYYY-MM-DD`) is in `window`, which may run over New Year (11-15 to 03-31). */
export function inWindow(window: SwitchWindow, day: string): boolean {
  const md = day.slice(5, 10);
  return window.start <= window.end
    ? window.start <= md && md <= window.end
    : md >= window.start || md <= window.end;
}

/** Whether `of` is on on `day` (`YYYY-MM-DD`, New York). */
export function isOn(of: Switch, day: string): boolean {
  if (of.mode === 'schedule') return of.window === undefined || inWindow(of.window, day);
  return of.mode === 'on';
}

/** A switch as it was set from `at` on, from its log. */
export interface SwitchSetting {
  readonly at: Date;
  readonly value: Switch;
}

/**
 * Whether a switch was on at `at`, on `day` (`YYYY-MM-DD`, New York), as it was set then:
 * `history` (the oldest first) says how it was set from each change on, so a switch turned on or
 * off by hand decides only what came after. Before its first change it counts as that first
 * setting; with no history at all, as `current`.
 */
export function wasOn(
  history: readonly SwitchSetting[],
  current: readonly Switch[],
): (id: string, at: Date, day: string) => boolean {
  const byId = new Map<string, SwitchSetting[]>();
  for (const setting of history) {
    const list = byId.get(setting.value.id) ?? [];
    list.push(setting);
    byId.set(setting.value.id, list);
  }
  const now = new Map(current.map((each) => [each.id, each]));
  return (id, at, day) => {
    const settings = byId.get(id);
    const setting =
      settings === undefined
        ? now.get(id)
        : (settings.findLast((each) => each.at.getTime() <= at.getTime()) ?? settings[0])?.value;
    return setting !== undefined && isOn(setting, day);
  };
}

/** Adds a switch, or replaces every field of one. */
export const SwitchEdit = z
  .strictObject({
    id: SwitchId.meta({ description: 'Its id, camelCase, such as `winter`. Never changes.' }),
    label: z.string().trim().min(1).max(80).meta({ description: 'What it is for, for admins.' }),
    mode: SwitchMode.meta({
      description: '`on` or `off` by hand, or `schedule`: on only in its window, every year.',
    }),
    window: z
      .strictObject({
        start: MonthDay.meta({ description: 'First day, `MM-DD`, New York time.' }),
        end: MonthDay.meta({
          description: 'Last day, `MM-DD`; may be before start (over New Year).',
        }),
      })
      .optional()
      .meta({
        description: 'The days of every year it is on, both included; needed for `schedule`.',
      }),
  })
  .refine(({ mode, window }) => mode !== 'schedule' || window !== undefined, {
    message: 'a switch on a schedule needs its window',
    path: ['window'],
  });
export type SwitchEdit = z.infer<typeof SwitchEdit>;
