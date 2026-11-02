import { expiresAfterApproval, type ApprovedMeme, type MemePhrase } from '../../domain/meme.js';
import { MemeExpiryBeforeApprovalError } from '../../errors.js';
import type { MemeStore } from '../../ports.js';

export interface AddApprovedMemesInput {
  readonly memes: readonly ApprovedMeme[];
  /** When Tracy approved them; a meme is used from then until it expires or is turned off. */
  readonly approvedAt: Date;
}

export interface AddedMemes {
  readonly added: MemePhrase[];
  /** Phrases the library already had, left unchanged. */
  readonly alreadyThere: MemePhrase[];
}

/** Adds the memes Tracy approved to the library. Adding the same batch again changes nothing. */
export async function addApprovedMemes(
  deps: { readonly store: MemeStore },
  { memes, approvedAt }: AddApprovedMemesInput,
): Promise<AddedMemes> {
  const early = memes.find(({ expiresAt }) => !expiresAfterApproval(expiresAt ?? null, approvedAt));
  if (early !== undefined) throw new MemeExpiryBeforeApprovalError(early.phrase);
  const added = await deps.store.add(memes, approvedAt);
  const fresh = new Set(added);
  const phrases = new Set(memes.map(({ phrase }) => phrase));
  return { added, alreadyThere: [...phrases].filter((phrase) => !fresh.has(phrase)) };
}
