// From sponge-ai-lab/engineering-skills (errors skill, templates/index.ts), with `@project`
// renamed to `@wildcard`.

/**
 * @wildcard/errors: the base every error extends. Supporting package: no
 * business logic.
 *
 * Each package keeps its own named errors (`UserNotFoundError` stays in the
 * users package) and extends `AppError`, so an app can turn any of them into a
 * response the same way. `status` is one of the error statuses, each with a
 * fixed HTTP status; `reason` says exactly what went wrong; the message is for
 * people. Apps answer HTTP requests with RFC 9457 problem details built by
 * `toProblemDetails`.
 */

/**
 * The error statuses and the HTTP status each maps to. The ones used most:
 *
 * - `INVALID_ARGUMENT`: the request itself is wrong; sending it again won't help.
 * - `FAILED_PRECONDITION`: the request is fine, but the system isn't in a state
 *   that allows it (an email address isn't verified yet). Fix the state first.
 * - `NOT_FOUND`: the thing asked for doesn't exist.
 * - `ALREADY_EXISTS`: the thing being created already exists.
 * - `ABORTED`: another write got there first. Read again and retry.
 * - `PERMISSION_DENIED`: the caller is known but may not do this.
 * - `UNAUTHENTICATED`: the caller's credentials are missing or bad.
 * - `UNAVAILABLE`: something we depend on is down; try again later.
 */
export const HTTP_STATUS = {
  INVALID_ARGUMENT: 400,
  FAILED_PRECONDITION: 400,
  OUT_OF_RANGE: 400,
  UNAUTHENTICATED: 401,
  PERMISSION_DENIED: 403,
  NOT_FOUND: 404,
  ABORTED: 409,
  ALREADY_EXISTS: 409,
  RESOURCE_EXHAUSTED: 429,
  CANCELLED: 499,
  DATA_LOSS: 500,
  UNKNOWN: 500,
  INTERNAL: 500,
  UNIMPLEMENTED: 501,
  UNAVAILABLE: 503,
  DEADLINE_EXCEEDED: 504,
} as const;
export type ErrorStatus = keyof typeof HTTP_STATUS;

/**
 * An error the app expects and can explain to the caller. Anything thrown that is
 * not a `AppError` is a bug, and apps answer it as `INTERNAL`.
 */
export abstract class AppError extends Error {
  abstract override readonly name: string;
  /** Stable and machine-readable, e.g. `USER_NOT_FOUND`. Never reworded. */
  abstract readonly reason: string;
  /** The general kind of error this is, e.g. `NOT_FOUND`. */
  abstract readonly status: ErrorStatus;
}

/** True for any error one of our packages threw on purpose. */
export function isAppError(error: unknown): error is AppError {
  return error instanceof AppError;
}

/**
 * True when `error` carries this `code` property, as errors from Node
 * (`ENOENT`) and Postgres (`23505`) do. Use it to
 * recognise a library's error before turning it into a package's own.
 */
export function hasErrorCode(error: unknown, code: string): boolean {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === code;
}

/** The HTTP reason phrase for each status `HTTP_STATUS` uses. */
const TITLE: Record<(typeof HTTP_STATUS)[ErrorStatus], string> = {
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  409: 'Conflict',
  429: 'Too Many Requests',
  499: 'Client Closed Request',
  500: 'Internal Server Error',
  501: 'Not Implemented',
  503: 'Service Unavailable',
  504: 'Gateway Timeout',
};

/**
 * An RFC 9457 problem details body (`application/problem+json`). `reason` and
 * `errorStatus` are extension members, so a client can tell apart errors
 * that share an HTTP status.
 */
export interface ProblemDetails {
  readonly type: 'about:blank';
  readonly title: string;
  readonly status: number;
  readonly detail: string;
  readonly reason: string;
  readonly errorStatus: ErrorStatus;
}

/**
 * The problem details body to answer with when a request fails with `error`.
 * An error that isn't a `AppError` is a bug: the caller gets a plain
 * `INTERNAL` answer, never its message, which may hold internals.
 */
export function toProblemDetails(error: unknown): ProblemDetails {
  const { status, reason, detail } = isAppError(error)
    ? { status: error.status, reason: error.reason, detail: error.message }
    : {
        status: 'INTERNAL' as const,
        reason: 'INTERNAL',
        detail: 'Something went wrong on our side.',
      };
  const http = HTTP_STATUS[status];
  return {
    type: 'about:blank',
    title: TITLE[http],
    status: http,
    detail,
    reason,
    errorStatus: status,
  };
}
