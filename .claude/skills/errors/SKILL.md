---
name: errors
description: How code fails. When to throw and when to return a result, how to define a package's error on the shared `AppError` base, how to pick its status, and how apps turn errors into responses. Use before adding or changing an error class, a `throw`, or the error handling in an app, and when reviewing any of these.
---

# Errors

Every failure a caller can act on is a named error class that extends `AppError` from `@<scope>/errors`. Apps turn any of them into a response in one place, so a new error needs no app change.

Start the `errors` package from this skill's `templates/index.ts`: the base class, the status list with its HTTP mapping, `toProblemDetails` and `hasErrorCode`.

## Throw, return, or crash

| Situation | Do | Example |
| --- | --- | --- |
| The answer *is* a pass or a fail: checking something is the point of the call | Return a result value. Never throw for an expected "no" | `validate()` returns the failed checks; `checkSignature()` returns `{ ok: false, problem }` |
| The caller asked for something the system refuses or can't find | Throw the package's own `AppError` subclass | `UserNotFoundError`, `DocumentChangedError` |
| Our own code or data is broken: a "can't happen" invariant | `throw new Error('…')`. It's a bug, not part of the API; apps answer it as `500 INTERNAL` and never show its message | `user ${id} was not loaded` |

## Define an error

One class per failure, in the package that throws it (`src/errors.ts`), exported from the package's `index.ts`:

```ts
import { AppError } from '@<scope>/errors';

/** Thrown when a document changed between being read and being written. Read again and retry. */
export class DocumentChangedError extends AppError {
  override readonly name = 'DocumentChangedError';
  readonly reason = 'DOCUMENT_CHANGED';
  readonly status = 'ABORTED';

  constructor(readonly documentId: string) {
    super(`Document ${documentId} changed since it was read`);
  }
}
```

- **`name`**: the class name, fixed.
- **`reason`**: the exact failure, `SCREAMING_SNAKE_CASE` starting with the noun it's about (`DOCUMENT_CHANGED`, `INVALID_DOCUMENT`). Clients and logs match on it, so it never changes once merged; a different failure gets a new reason. It is called `reason`, not `code`, so nobody reads it as an HTTP status code.
- **`status`**: the general kind of failure, from the list below. Apps pick the response from it.
- **Fields**: the ids the error is about, as `readonly` constructor parameters, so callers don't parse the message.
- **Message**: one plain sentence for people, naming the id. Errors can reach users, so no internals: no SQL, stacks, file paths, keys or hashes .
- **Cause**: when wrapping a library error, pass it on: `super(message, { cause })`.
- A doc comment saying when it's thrown, and what the caller should do if that isn't obvious.

Don't:

- Make a shared or generic error (`NotFoundError`, `ValidationError`). Each package names its own failures; only the base is shared.
- Put an HTTP status, MCP error code or any transport detail on an error. `status` is the only link to a response.
- Throw a plain `Error` for something the caller can fix: that answers 500.
- Match on messages. Recognise a library's error with `hasErrorCode(error, '23505')`, and our errors with `instanceof` or `reason`.

## Pick the status

| Status | HTTP | When | Caller should |
| --- | --- | --- | --- |
| `INVALID_ARGUMENT` | 400 | The request itself is wrong, whatever the state: a blank name, a bad cursor | Fix the request |
| `FAILED_PRECONDITION` | 400 | The request is fine, but the state doesn't allow it yet: email not verified, draft already published | Change the state first; retrying as is won't help |
| `OUT_OF_RANGE` | 400 | Past the end of something that can grow: a page beyond the last | Ask for less |
| `UNAUTHENTICATED` | 401 | No credentials, or bad ones | Sign in |
| `PERMISSION_DENIED` | 403 | We know who's asking, and they may not do this | Stop |
| `NOT_FOUND` | 404 | The thing asked for doesn't exist, or the caller may not know it exists | Check the id |
| `ALREADY_EXISTS` | 409 | Creating something that's already there | Use the existing one |
| `ABORTED` | 409 | Another write got there first (stale version, lost race) | Read again and retry |
| `RESOURCE_EXHAUSTED` | 429 | A quota or rate limit is used up | Wait, or ask for a higher limit |
| `UNAVAILABLE` | 503 | Something we depend on is down for now | Retry later |
| `DEADLINE_EXCEEDED` | 504 | Something we depend on didn't answer in time | Retry later |
| `UNIMPLEMENTED` | 501 | A path that isn't built yet | Don't call it |
| `INTERNAL`, `DATA_LOSS`, `UNKNOWN` | 500 | We broke something or lost data | Report it |

The usual mix-ups:

- **Exists, stale or not ready?** Creating a duplicate is `ALREADY_EXISTS`. Losing a race with another writer is `ABORTED`. Asking at the wrong time (not verified, already published, expired) is `FAILED_PRECONDITION`.
- **Bad input or bad state?** If the same request could succeed later without changing it, it's `FAILED_PRECONDITION`; if it never could, it's `INVALID_ARGUMENT`.
- **Forbidden or not found?** When admitting the thing exists would leak something (someone else's order), answer `NOT_FOUND` or one `PERMISSION_DENIED` for every case, never different answers.

The list is fixed: add a status only by changing `@<scope>/errors` in its own PR.

## At the edge

Apps hold the only mapping from errors to responses:

- **HTTP** answers with `toProblemDetails(error)` as `application/problem+json` (RFC 9457): `status` from `HTTP_STATUS`, `detail` from the message, `reason` and `errorStatus` as extension members. Anything that isn't an `AppError` becomes a generic `500 INTERNAL`; log the original, never send it.
- **MCP** tools return the same `reason`, `errorStatus` and message as a tool error.
- An app may override the HTTP status for one error only when a protocol requires it (a storage upload that's too large answering `413`), next to that route, never on the error.

## Test it

- Assert the observable failure: `await expect(call).rejects.toMatchObject({ reason: 'DOCUMENT_CHANGED' })` or `.rejects.toThrow('Document d1 changed since it was read')`. Never `toBeInstanceOf`; ESLint bans it.
- Keep a table test of every error in the package with its `reason` and `status` (`src/errors.test.ts`), so a changed status is a visible diff.
- Storage errors are proven on real Postgres: the constraint fires and the store maps it to the package's error.

## Enforced

ESLint rejects a class in `packages/*/src` that extends `Error` directly; extend `AppError` instead. The contract package and the errors package itself are exempt; the rule is in the `verification` skill's `templates/eslint.config.js`.
