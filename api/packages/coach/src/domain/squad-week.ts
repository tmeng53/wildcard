// A squad's week as the coach sees it: who is in the squad, and what they checked in, with the
// reactions and comments on it. The model never sees a member's id: each member is 队员N, by
// the order they joined, with the nickname they gave their character.

/** What a member checked in. */
export type CheckInKind = 'trained' | 'healthyMeal' | 'cheatMeal' | 'disclaimer';

export interface WeekCheckIn {
  readonly id: string;
  readonly member: string;
  /** The member's own day, `YYYY-MM-DD`. */
  readonly day: string;
  readonly createdAt: Date;
  readonly kind: CheckInKind;
  /** A 练了's sport, by its name. */
  readonly sport?: string;
  readonly minutes?: number;
  /** The member's line: a caption, or a 请假条's text. */
  readonly text?: string;
  /** How many teammates reacted to it. */
  readonly reactions: number;
  /** Teammates' comments, oldest first. */
  readonly comments: readonly { readonly member: string; readonly text: string }[];
}

export interface SquadWeek {
  /** The Monday the week starts, `YYYY-MM-DD`. */
  readonly weekStart: string;
  /** Everyone in the squad now, in the order they joined. */
  readonly members: readonly { readonly member: string; readonly nickname?: string }[];
  /** The week's check-ins shared to the squad, oldest first. */
  readonly checkIns: readonly WeekCheckIn[];
}

/** Each member's name for the model: 队员1, 队员2, … by the order they joined. */
export function rosterOf(week: Pick<SquadWeek, 'members'>): ReadonlyMap<string, string> {
  return new Map(week.members.map(({ member }, index) => [member, `队员${String(index + 1)}`]));
}

const KIND_WORDS: Readonly<Record<CheckInKind, string>> = {
  trained: '练了',
  healthyMeal: '健康餐',
  cheatMeal: '坦白放纵餐',
  disclaimer: '请假条',
};

const WEEKDAYS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

/** `10-27 周二`, for a `YYYY-MM-DD` day. */
function dayWords(day: string): string {
  return `${day.slice(5)} ${WEEKDAYS[new Date(`${day}T00:00:00Z`).getUTCDay()] ?? ''}`;
}

/** One check-in as a line the model reads. */
export function checkInLine(checkIn: WeekCheckIn, roster: ReadonlyMap<string, string>): string {
  const who = roster.get(checkIn.member) ?? '队员';
  const parts = [`${dayWords(checkIn.day)} ${who} ${KIND_WORDS[checkIn.kind]}`];
  if (checkIn.sport !== undefined) parts.push(checkIn.sport);
  if (checkIn.minutes !== undefined) parts.push(`${String(checkIn.minutes)} 分钟`);
  if (checkIn.text !== undefined) parts.push(`「${checkIn.text}」`);
  const line = [parts.join(' ')];
  if (checkIn.reactions > 0) line.push(`${String(checkIn.reactions)} 个表情`);
  if (checkIn.comments.length > 0) {
    const comments = checkIn.comments.map(
      ({ member, text }) => `${roster.get(member) ?? '队员'}「${text}」`,
    );
    line.push(`评论：${comments.join('；')}`);
  }
  return line.join(' · ');
}

/** The week as the `squad_week` tool answers it. */
export function weekText(week: SquadWeek): string {
  const roster = rosterOf(week);
  const members = week.members.map(
    ({ member, nickname }) =>
      `${roster.get(member) ?? '队员'}${nickname === undefined ? '' : `（昵称：${nickname}）`}`,
  );
  const checkIns = week.checkIns.map((checkIn) => `- ${checkInLine(checkIn, roster)}`);
  return [
    `本周从 ${week.weekStart}（周一）开始。`,
    `队员：${members.join('，')}`,
    checkIns.length === 0 ? '这周还没有人打卡。' : `打卡：\n${checkIns.join('\n')}`,
  ].join('\n');
}
