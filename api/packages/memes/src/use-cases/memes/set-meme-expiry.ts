import { expiresAfterApproval, type MemePhrase } from '../../domain/meme.js';
import { MemeExpiryBeforeApprovalError, MemeNotFoundError } from '../../errors.js';
import type { MemeStore } from '../../ports.js';

export interface SetMemeExpiryInput {
  readonly phrase: MemePhrase;
  /** When it stops being used; null to keep it in use until it is turned off. */
  readonly expiresAt: Date | null;
}

/**
 * Sets when a meme stops being used, or clears it so the meme stays in use until it is turned
 * off. An expired meme given a later expiry, or none, is used again.
 */
export async function setMemeExpiry(
  deps: { readonly store: MemeStore },
  { phrase, expiresAt }: SetMemeExpiryInput,
): Promise<void> {
  const approvedAt = await deps.store.approvedAt(phrase);
  if (approvedAt === undefined) throw new MemeNotFoundError(phrase);
  if (!expiresAfterApproval(expiresAt, approvedAt)) throw new MemeExpiryBeforeApprovalError(phrase);
  if (!(await deps.store.setExpiry(phrase, expiresAt))) throw new MemeNotFoundError(phrase);
}
