import { randomInt } from 'node:crypto';

import {
  INVITE_CODE_ALPHABET,
  INVITE_CODE_LENGTH,
  InviteCode,
  type InviteCodes,
} from '../domain/invite-code.js';

/** Invite codes from Node's cryptographic random numbers, each letter equally likely. */
export const randomInviteCodes: InviteCodes = () =>
  InviteCode.parse(
    Array.from({ length: INVITE_CODE_LENGTH }, () =>
      INVITE_CODE_ALPHABET.charAt(randomInt(INVITE_CODE_ALPHABET.length)),
    ).join(''),
  );
