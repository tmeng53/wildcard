import { z } from 'zod';

/**
 * The letters an invite code is made of: digits and capitals without the ones people confuse
 * (0 and O, 1, I and L), so a code read aloud or typed from a screenshot comes out right.
 */
export const INVITE_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/**
 * 8 letters from 31: about 850 billion codes, so guessing one that works takes far more tries
 * than anyone gets, while a friend can still type it. Most people never type it: an invite
 * link carries it.
 */
export const INVITE_CODE_LENGTH = 8;

const INVITE_CODE = new RegExp(`^[${INVITE_CODE_ALPHABET}]{${String(INVITE_CODE_LENGTH)}}$`);

/**
 * A squad's invite code, such as `K7M2QX9P`. Read forgivingly, since people type it: lower case
 * is upper case, and spaces and dashes (`k7m2-qx9p`) are left out.
 */
export const InviteCode = z
  .string()
  .max(64)
  .transform((code) => code.replace(/[\s-]/g, '').toUpperCase())
  .pipe(z.string().regex(INVITE_CODE, 'Must be an 8-letter invite code'))
  .brand<'InviteCode'>();
export type InviteCode = z.infer<typeof InviteCode>;

/** Makes a new random invite code. Codes are unique; the store refuses a repeat. */
export type InviteCodes = () => InviteCode;
