// How long each kind of line a coach writes for members may be, by the language it is written in
// (Tracy, 2026-11-12): an English word takes several letters where Chinese takes one or two
// characters, so English gets its own, longer limits.

/** The languages a line's limit tells apart. */
export type LineLanguage = 'chinese' | 'english';

/** Each kind of line a coach writes for members, and its longest in characters per language. */
export const LINE_LIMITS = {
  /** A reply to a check-in, or an answer to a member's reply: as long as a member's comment. */
  reply: { chinese: 100, english: 200 },
  /** The day's 战术板 line, or a 便条 to one member. */
  note: { chinese: 60, english: 120 },
  /** The line a gift comes with. */
  gift: { chinese: 60, english: 120 },
  /** The outgoing coach's letter to the next. */
  letter: { chinese: 200, english: 400 },
  /** A challenge's title: only what to do. */
  challengeTitle: { chinese: 8, english: 16 },
  /** A challenge's unit for its amount. */
  challengeUnit: { chinese: 4, english: 8 },
  /** The small line under a challenge's title. */
  challengeLine: { chinese: 24, english: 48 },
} as const satisfies Record<string, Record<LineLanguage, number>>;

export type LineKind = keyof typeof LINE_LIMITS;

/**
 * The language a line is held to: English when it has more Latin letters than Chinese
 * characters, so a Chinese line naming 「Hannah」 is still Chinese, and an English one naming
 * 「毛头」 is still English.
 */
export function lineLanguageOf(text: string): LineLanguage {
  const latin = text.match(/[A-Za-z]/gu)?.length ?? 0;
  const chinese = text.match(/\p{Script=Han}/gu)?.length ?? 0;
  return latin > chinese ? 'english' : 'chinese';
}

/** How many characters a line has, as the database counts them. */
function charactersIn(text: string): number {
  return text.match(/./gsu)?.length ?? 0;
}

/** The longest a line of this kind may be in any language: what the database and the wire hold. */
export function longestLine(kind: LineKind): number {
  return Math.max(...Object.values(LINE_LIMITS[kind]));
}

/** Whether a line fits its kind's limit in the language it is written in. */
export function fitsLine(text: string, kind: LineKind): boolean {
  return charactersIn(text) <= LINE_LIMITS[kind][lineLanguageOf(text)];
}

/** How the model is told a kind's limits: 「不超过 100 字，英文不超过 200 个字符」. */
export function limitWords(kind: LineKind): string {
  const { chinese, english } = LINE_LIMITS[kind];
  return `不超过 ${String(chinese)} 字，英文不超过 ${String(english)} 个字符`;
}

/** Why a line is too long for its kind, or `undefined` when it fits. */
export function lengthProblem(text: string, kind: LineKind): string | undefined {
  if (fitsLine(text, kind)) return undefined;
  const length = charactersIn(text);
  return lineLanguageOf(text) === 'english'
    ? `太长了：${String(length)} 个字符，英文最多 ${String(LINE_LIMITS[kind].english)} 个。`
    : `太长了：${String(length)} 字，最多 ${String(LINE_LIMITS[kind].chinese)} 字。`;
}
