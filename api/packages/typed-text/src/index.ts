import { z } from 'zod';

// @wildcard/typed-text: the rules for text people type (a caption, a disclaimer, a name). They
// match the app's own checks (ios/Packages/Contracts), which trim with Swift's
// `.whitespacesAndNewlines` and count `Character`s, so text the app accepts is accepted here
// and nothing more.

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
 * What a name may not hold, as the contract's `CustomSport`: control characters, and any
 * Unicode space other than a plain space and the ideographic space U+3000.
 */
const NOT_A_NAME = /\p{Cc}|(?![ \u3000])\p{White_Space}/u;

/** A bidi control: U+202E, for one, flips the text after it. */
const DIRECTION_CONTROL = /\p{Bidi_Control}/u;

/** Something people can see: not a format character (a zero-width joiner) or a space. */
const VISIBLE = /[^\p{Cf}\p{White_Space}]/u;

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

/**
 * A typed text: trimmed, then 1 to `max` characters, never blank, on one line if asked. The
 * OpenAPI document carries `max` as `x-max-characters`, which the app's limits are tested against.
 */
export function typedText({
  max,
  oneLine,
  description,
}: {
  readonly max: number;
  readonly oneLine: boolean;
  readonly description: string;
}) {
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
    })
    .meta({ description, 'x-max-characters': max });
}

/** A name (a custom sport, a squad): trimmed, 1 to `max` characters, one line with plain spaces. */
export function nameText({
  max,
  description,
}: {
  readonly max: number;
  readonly description: string;
}) {
  return (
    typedText({ max, oneLine: true, description })
      .refine((name) => !NOT_A_NAME.test(name), {
        message: 'Must be one line, with no tabs or unusual spaces',
      })
      // As the contract's `CustomSport`: no name that shows as blank (only format characters,
      // such as a lone zero-width joiner) or reads in a forced direction. Joiners inside a real
      // name, as in 🏃‍♀️, are fine; blank text is already refused above.
      .refine((name) => isBlank(name) || (VISIBLE.test(name) && !DIRECTION_CONTROL.test(name)), {
        message: 'Must show something readable, with no direction controls',
      })
  );
}

/**
 * Top-level domains a pasted link usually ends in. A bare `name.tld` counts as a link only with
 * one of these, so a word with a dot in it (`Mr.Bean`) is still text.
 */
const LINK_TLDS =
  'com|net|org|io|co|cn|me|app|xyz|cc|tv|ly|gg|ai|dev|link|top|info|us|ca|uk|hk|tw|jp|site|shop|vip|club';

/**
 * A link in typed text: a scheme (`https://`, `weixin://`), `www.`, or a bare domain such as
 * `abc.com`. Dots may be written as full-width `．` or `。`, as people do to get around filters.
 */
const LINK = new RegExp(
  String.raw`[a-z][a-z0-9+.-]*:\/\/|www[.．。]|[a-z0-9-]+[.．。](?:${LINK_TLDS})(?![a-z0-9])`,
  'iu',
);

/** True when the text holds something that reads as a link. */
export function containsLink(text: string): boolean {
  return LINK.test(text);
}
