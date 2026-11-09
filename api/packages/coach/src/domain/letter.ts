import type { Coach, CoachId } from './coach.js';
import type { SquadId } from './settings.js';

// The letter a coach leaves when its squad changes coach (换教练): the outgoing coach writes it
// once, in its own voice, to the squad and the next coach, saying goodbye and handing the squad
// over (Tracy, 2026-11-09), and the squad's members read it. It is never a briefing between
// coaches: the new coach keeps reading the squad's memory files, never the letter.

/** The longest letter, in characters; the database checks the same. */
export const LETTER_LIMIT = 200;

/** A change of coach the outgoing coach writes for: the hire that made it and both coaches. */
export interface Handover {
  /** The hire's row in the squad's hires and firings log, which names the change. */
  readonly hireEvent: number;
  readonly squad: SquadId;
  readonly from: CoachId;
  readonly to: CoachId;
  readonly at: Date;
}

/** One coach's time with a squad, from the hires and firings log, oldest first. */
export interface Tenure {
  readonly coach: CoachId;
  /** The squad's day it was hired and, unless it is the coach now, fired, `YYYY-MM-DD`. */
  readonly from: string;
  readonly until?: string;
}

/** A letter as members read it, with both coaches as the app draws them. */
export interface CoachLetter {
  readonly id: number;
  readonly squad: SquadId;
  readonly from: { readonly id: string; readonly name: string; readonly look: string };
  readonly to: { readonly id: string; readonly name: string; readonly look: string };
  /** The squad's day it was written on, `YYYY-MM-DD`, which it is dated. */
  readonly day: string;
  readonly text: string;
  readonly at: Date;
}

/**
 * The task for the outgoing coach: who takes over, what the squad's coaches were before (so a
 * coach coming back is greeted as one), what it remembers, and how a letter goes. Principles
 * only: what it says is its own.
 */
export function letterTask({
  to,
  history,
  names,
  nicknames,
  memory,
}: {
  readonly to: Pick<Coach, 'id' | 'name'>;
  /** The squad's coaches so far, oldest first, the change just made included. */
  readonly history: readonly Tenure[];
  /** Each coach's name, by id. */
  readonly names: ReadonlyMap<string, string>;
  /** Each member's nickname, by the name the model knows them by (队员N). */
  readonly nicknames: ReadonlyMap<string, string>;
  /** The coach's memory, as every task shows it. */
  readonly memory: string;
}): string {
  const nameOf = (coach: string) => names.get(coach) ?? coach;
  const tenures = history.map(
    ({ coach, from, until }) => `- ${nameOf(coach)}：${from} 到 ${until ?? '现在'}`,
  );
  // The change just made is the last tenure: was the new coach here before it?
  const before = history.slice(0, -1);
  const back = before.some(({ coach }) => coach === to.id);
  return [
    `这个小队换教练了：你被换掉，接手的是${to.name}。走之前给小队和${to.name}留一封告别信，全队都会看到。`,
    `这个小队请过的教练（先后顺序）：\n${tenures.join('\n')}`,
    ...(back ? [`${to.name}以前带过这个小队，这次是回来。`] : []),
    `队员的昵称：\n${[...nicknames].map(([name, nickname]) => `- ${name}：${nickname}`).join('\n')}`,
    memory,
    [
      '怎么写：',
      `- 用你自己的口吻，对全队和${to.name}说：跟大家道别，把小队交给${to.name}。不客套，不煽情。`,
      '- 可以提跟这个小队一起的事，只挑大家乐意被当众提起的；记性里没有的不编。',
      '- 这不是教练之间的交接笔记：不写谁住哪、做什么工作、私下说过什么，不写体重、身材、伤病。',
      '- 叫队员用昵称。',
      `- 只写正文，称呼和落款不写，最多 ${String(LETTER_LIMIT)} 字。写好用 write_letter 交。`,
    ].join('\n'),
  ].join('\n\n');
}

/**
 * Each coach's time with the squad, from its hires and firings log (oldest first), by the squad's
 * days: a hire opens a tenure, the firing after it closes it.
 */
export function tenuresOf(
  events: readonly {
    readonly kind: 'hired' | 'fired';
    readonly coach: CoachId;
    readonly day: string;
  }[],
): Tenure[] {
  const tenures: Tenure[] = [];
  let open: { coach: CoachId; from: string } | undefined;
  for (const { kind, coach, day } of events) {
    if (kind === 'hired') {
      if (open !== undefined) tenures.push(open);
      open = { coach, from: day };
    } else if (open?.coach === coach) {
      tenures.push({ ...open, until: day });
      open = undefined;
    }
  }
  if (open !== undefined) tenures.push(open);
  return tenures;
}
