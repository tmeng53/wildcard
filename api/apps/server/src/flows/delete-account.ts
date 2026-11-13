import { AppleAuthorizationCodeRequiredError } from '../errors.js';
import type { Log } from '../log.js';
import { UserId, type Accounts, type PhotoStorage, type RevokeAppleSignIn } from '../ports.js';

export interface DeleteAccountDependencies {
  readonly accounts: Accounts;
  readonly photos: PhotoStorage;
  /** Undefined until the Sign in with Apple key is configured; then Apple isn't told. */
  readonly revokeAppleSignIn: RevokeAppleSignIn | undefined;
  readonly log: Log;
  /** The demo accounts an admin made, which go with them; none for anyone else. */
  readonly demoAccountsOf: (member: UserId) => Promise<readonly string[]>;
  /** Whether the member is a demo account an admin made, whose phone is the admin's. */
  readonly isDemoAccount: (member: UserId) => Promise<boolean>;
}

/**
 * Deletes a member's account and everything that is theirs, as the App Store requires: their
 * Sign in with Apple grant, their photo files, then their user, which takes their profile,
 * check-ins (with their photos' records and audiences), squad memberships and weekly awards
 * with it in the database. A squad stays with its other members; one the member was the last in
 * goes with them (the database's cascade), and so do the demo accounts an admin made. Each step is safe to repeat, so a
 * failed deletion is retried from the start; Apple goes first because it needs a fresh code
 * the app can only get while the member is still signed in.
 */
export async function deleteAccount(
  deps: DeleteAccountDependencies,
  request: { readonly member: UserId; readonly appleAuthorizationCode: string | undefined },
): Promise<void> {
  const { member, appleAuthorizationCode } = request;
  if (await deps.isDemoAccount(member)) {
    // A demo account never signs in with Apple; a code sent with it is the admin's own grant.
  } else if (deps.revokeAppleSignIn === undefined) {
    if (appleAuthorizationCode !== undefined) {
      deps.log.warn('Sign in with Apple not revoked: no Apple key is configured', { member });
    }
  } else if (appleAuthorizationCode !== undefined) {
    await deps.revokeAppleSignIn(appleAuthorizationCode);
  } else if (await deps.accounts.signsInWithApple(member)) {
    // The server decides, not the app: an Apple account is never deleted with its grant left.
    throw new AppleAuthorizationCodeRequiredError();
  }
  // An admin's demo accounts first: nobody could switch to them once the admin is gone.
  for (const demo of await deps.demoAccountsOf(member)) {
    const account = UserId.parse(demo);
    await deps.photos.deleteAllOf(account);
    await deps.accounts.deleteUser(account);
  }
  await deps.photos.deleteAllOf(member);
  await deps.accounts.deleteUser(member);
  deps.log.info('account deleted', { member });
}
