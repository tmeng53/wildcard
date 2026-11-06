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

export const SWITCH_MODES = ['on', 'off', 'schedule', 'preview'] as const;
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
  /**
   * On, off, on only in `window`, or `preview`: on only for members who preview switches (in
   * `window` when it has one), off for everyone else.
   */
  readonly mode: SwitchMode;
  /** Its schedule; always there for one in `schedule` mode. */
  readonly window?: SwitchWindow;
  /** What the AI coach is told while it is on, such as 「今天是感恩节」; never shown in the app. */
  readonly coachNote?: string;
}

/** Whether `day` (`YYYY-MM-DD`) is in `window`, which may run over New Year (11-15 to 03-31). */
export function inWindow(window: SwitchWindow, day: string): boolean {
  const md = day.slice(5, 10);
  return window.start <= window.end
    ? window.start <= md && md <= window.end
    : md >= window.start || md <= window.end;
}

/** Whether `of` is on on `day` (`YYYY-MM-DD`, New York) for everyone: one in preview is off. */
export function isOn(of: Switch, day: string): boolean {
  switch (of.mode) {
    case 'schedule':
      return of.window === undefined || inWindow(of.window, day);
    case 'on':
      return true;
    case 'off':
    case 'preview':
      return false;
  }
}

/** A switch as it was set from `at` on, from its log. */
export interface SwitchSetting {
  readonly at: Date;
  readonly value: Switch;
}

/**
 * Whether a switch was on at `when.at`, on `when.day` (`YYYY-MM-DD`, New York), as it was set then:
 * `history` (the oldest first) says how it was set from each change on, so a switch turned on or
 * off by hand decides only what came after. Before its first change it counts as that first
 * setting; with no history at all, as `current`.
 */
export function wasOn(
  history: readonly SwitchSetting[],
  current: readonly Switch[],
): (id: string, when: { readonly at: Date; readonly day: string }) => boolean {
  const byId = new Map<string, SwitchSetting[]>();
  for (const setting of history) {
    const list = byId.get(setting.value.id) ?? [];
    list.push(setting);
    byId.set(setting.value.id, list);
  }
  const now = new Map(current.map((each) => [each.id, each]));
  return (id, { at, day }) => {
    const settings = byId.get(id);
    const setting =
      settings === undefined
        ? now.get(id)
        : (settings.findLast((each) => each.at.getTime() <= at.getTime()) ?? settings[0])?.value;
    return setting !== undefined && isOn(setting, day);
  };
}

/** Whether `of` is on on `day` for a member who previews switches: one in preview follows its window. */
export function isOnForPreviewer(of: Switch, day: string): boolean {
  return of.mode === 'preview'
    ? of.window === undefined || inWindow(of.window, day)
    : isOn(of, day);
}

/**
 * How one member sees the switches: whether they preview them (see the `preview` mode) and how
 * many days from New York's today they pretend it is, for switches only.
 */
export interface SwitchView {
  readonly previewer: boolean;
  readonly dayOffset: number;
}

/** Everyone who doesn't preview: the real day, no switch in preview. */
export const PLAIN_VIEW: SwitchView = { previewer: false, dayOffset: 0 };

/** A day offset as an admin sets it: whole days, at most a bit over a year either way. */
export const DayOffset = z.int().min(-400).max(400);

/** What the AI coach is told while a switch is on, in Chinese, as the coach speaks. */
export const CoachNote = z
  .string()
  .trim()
  .min(1)
  .max(120)
  .meta({
    description:
      'What the AI coach is told while the switch is on (for everyone, not in preview), in ' +
      'Chinese, such as 「今天是感恩节，TURKEY TROT 开张了」. Never shown in the app. Left out, the ' +
      'coach is told nothing.',
  });

/** The coach's notes of every switch on on `day` (`YYYY-MM-DD`, New York) for everyone. */
export function coachNotesOn(switches: readonly Switch[], day: string): string[] {
  return switches.flatMap((each) =>
    each.coachNote !== undefined && isOn(each, day) ? [each.coachNote] : [],
  );
}

/** Adds a switch, or replaces every field of one. */
export const SwitchEdit = z
  .strictObject({
    id: SwitchId.meta({ description: 'Its id, camelCase, such as `winter`. Never changes.' }),
    label: z.string().trim().min(1).max(80).meta({ description: 'What it is for, for admins.' }),
    mode: SwitchMode.meta({
      description:
        '`on` or `off` by hand, `schedule`: on only in its window, every year, or `preview`: ' +
        'on (in its window, if any) only for members who preview switches (set_switch_preview).',
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
    coachNote: CoachNote.optional(),
  })
  .refine(({ mode, window }) => mode !== 'schedule' || window !== undefined, {
    message: 'a switch on a schedule needs its window',
    path: ['window'],
  });
export type SwitchEdit = z.infer<typeof SwitchEdit>;
