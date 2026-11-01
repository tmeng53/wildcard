import type { Coach } from './coach.js';
import type { CoachSettings } from './settings.js';
import { checkInLine, rosterOf, type SquadWeek } from './squad-week.js';
import type { WakeReason } from './wake.js';

// What the model reads: the standing instructions (the rules every coach follows, then this
// coach's identity and soul) and each wake's task. Chinese, as the coach speaks.

/** The longest 战术板 line, in characters; the database checks the same. */
export const NOTE_LIMIT = 60;

/** The standing instructions for a coach. */
export function instructionsOf(settings: Pick<CoachSettings, 'rules'>, coach: Coach): string {
  return [
    settings.rules,
    `你的人设：\n名字：${coach.name}\n口头禅：${coach.catchphrase}\n资历：${coach.credentials}\n风格：${coach.style}`,
    coach.soul,
  ].join('\n\n');
}

/** A file's size, as the task lists it. */
function sizeWords(body: string | undefined): string {
  return body === undefined || body === '' ? '空' : `${String(body.length)} 字`;
}

/**
 * The task for one wake: what happened, the files there are, and what the coach may do this
 * time. `undefined` when there is nothing to wake for (the check-in left the squad's week).
 */
export function taskOf({
  reason,
  week,
  files,
  recentNotes,
}: {
  readonly reason: WakeReason;
  readonly week: SquadWeek;
  /** Each file the model may use, by the path it sees, with its body when it has one. */
  readonly files: ReadonlyMap<string, string | undefined>;
  /** The squad's last 战术板 lines, newest first. */
  readonly recentNotes: readonly { readonly day: string; readonly text: string }[];
}): string | undefined {
  const fileList = [...files].map(([path, body]) => `${path}（${sizeWords(body)}）`).join('，');
  const filesLine = `你的文件：${fileList}。用 read_file 读，用 edit_file 改。`;
  if (reason.kind === 'checkIn') {
    const checkIn = week.checkIns.find(({ id }) => id === reason.checkIn);
    if (checkIn === undefined) return undefined;
    return [
      `小队刚有人打卡：${checkInLine(checkIn, rosterOf(week))}`,
      filesLine,
      '这一次你不发言，只整理记忆：需要的话先用 squad_week 看这周的情况，有值得记住的（新的梗、习惯、重要的事）就写进文件，没有就什么都不做。',
    ].join('\n\n');
  }
  const notes =
    recentNotes.length === 0
      ? '你还没在战术板上写过。'
      : `你最近写过：\n${recentNotes.map(({ day, text }) => `- ${day}：${text}`).join('\n')}\n别重复。`;
  return [
    `新的一天：${reason.day}。`,
    filesLine,
    `先用 squad_week 看看小队这周，读读你的文件，然后用 post_note 在小队的战术板上写今天的一句（不超过 ${String(NOTE_LIMIT)} 字），全队都会看到。`,
    notes,
    '没什么值得说的，就不写。学到值得记的，顺手改文件。',
  ].join('\n\n');
}
