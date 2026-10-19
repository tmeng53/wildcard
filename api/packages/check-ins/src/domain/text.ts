import { z } from 'zod';

// Text rules shared by every check-in field people type. They match the app's contract
// (ios/Packages/Contracts), which trims with Swift's `.whitespacesAndNewlines` and counts
// `Character`s, so text the app accepts is accepted here and nothing more.

/**
 * The spaces and line breaks Swift's `.whitespacesAndNewlines` trims, listed by checking every
 * Unicode scalar (swift:6.0 on Linux). JavaScript's `trim()` differs: it also trims U+FEFF.
 * U+200B counts as a space in Foundation on Linux but maybe not on Apple, so it isn't trimmed,
 * but text made only of it is refused.
 */
const CONTRACT_SPACES =
  '\u0009\u000A\u000B\u000C\u000D\u0020\u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004' +
  '\u2005\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000';

/** The line breaks Swift's `Character.isNewline` knows. A one-line text holds none of them. */
const LINE_BREAKS = '\u000A\u000B\u000C\u000D\u0085\u2028\u2029';

/**
 * What a custom sport name may not hold, as the contract's `CustomSport`: control characters,
 * and any Unicode space other than a plain space and the ideographic space U+3000.
 */
const NOT_A_NAME = /\p{Cc}|(?![ \u3000])\p{White_Space}/u;

/** Bounds the raw string before the per-character checks, so a huge body costs nothing. */
const RAW_LIMIT = 1000;

const graphemes = new Intl.Segmenter('und', { granularity: 'grapheme' });

/** Characters as people see them (a Chinese character or an emoji is one), as Swift counts. */
export function graphemeCount(text: string): number {
  return Array.from(graphemes.segment(text)).length;
}

/** `text` without the contract's spaces and line breaks at either end. */
export function trimContractSpaces(text: string): string {
  let start = 0;
  let end = text.length;
  while (start < end && CONTRACT_SPACES.includes(text.charAt(start))) start += 1;
  while (end > start && CONTRACT_SPACES.includes(text.charAt(end - 1))) end -= 1;
  return text.slice(start, end);
}

/** True when the text is only U+200B and the contract's spaces, or empty. */
function isBlank(text: string): boolean {
  for (const char of text) {
    if (char !== '\u200B' && !CONTRACT_SPACES.includes(char)) return false;
  }
  return true;
}

/** A typed text: trimmed, then 1 to `max` characters, never blank, on one line if asked. */
function typedText({ max, oneLine }: { readonly max: number; readonly oneLine: boolean }) {
  return z
    .string()
    .max(RAW_LIMIT)
    .transform(trimContractSpaces)
    .superRefine((text, context) => {
      if (isBlank(text)) {
        context.addIssue({ code: 'custom', message: 'Must not be blank' });
        return;
      }
      if (oneLine && Array.from(text).some((char) => LINE_BREAKS.includes(char))) {
        context.addIssue({ code: 'custom', message: 'Must be one line' });
      }
      const count = graphemeCount(text);
      if (count > max) {
        context.addIssue({ code: 'custom', message: `Must be at most ${String(max)} characters` });
      }
    });
}

/** The optional line under a 练了 or a meal: trimmed, 1 to 60 characters, one line. */
export const Caption = typedText({ max: 60, oneLine: true }).meta({
  description: 'Trimmed, then 1 to 60 characters as people see them, on one line.',
});

/** A 今日免责声明: trimmed, 1 to 40 characters, and it may span lines. */
export const DisclaimerText = typedText({ max: 40, oneLine: false }).meta({
  description: 'Trimmed, then 1 to 40 characters as people see them; may span lines.',
});

/** 其他: a sport the member names: trimmed, 1 to 20 characters, one line with plain spaces. */
export const CustomSportName = typedText({ max: 20, oneLine: true })
  .refine((name) => !NOT_A_NAME.test(name), {
    message: 'Must be one line, with no tabs or unusual spaces',
  })
  .meta({ description: 'Trimmed, then 1 to 20 characters as people see them, on one line.' });
