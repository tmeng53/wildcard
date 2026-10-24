import { AsyncLocalStorage } from 'node:async_hooks';

/**
 * Structured logs: one JSON object per line on stdout, in the shape Cloud Run's logging reads
 * (`severity`, `message`, then any fields). Never the console.
 * https://cloud.google.com/run/docs/logging#writing_structured_logs
 *
 * Every entry is redacted as it is written (see `redact`): a log may name a member by id, never
 * by anything they typed, their email, a token or a photo's path.
 */
export interface Log {
  error(message: string, fields?: Record<string, unknown>): void;
  warn(message: string, fields?: Record<string, unknown>): void;
  info(message: string, fields?: Record<string, unknown>): void;
}

/** The request an entry is written in, which `inRequest` sets for everything a request runs. */
export interface RequestScope {
  /** The trace Cloud Run gave the request (32 hex digits), which the response sends back. */
  readonly traceId: string;
  /** The span Cloud Run gave the request, as 16 hex digits; undefined when it sent none. */
  readonly spanId: string | undefined;
  /** Fields every entry in the request carries, such as which job it runs. */
  readonly fields: Record<string, unknown>;
}

const requests = new AsyncLocalStorage<RequestScope>();

/** Runs `work` so that every entry it logs, however deep, carries the request's trace. */
export function inRequest<T>(scope: Omit<RequestScope, 'fields'>, work: () => T): T {
  return requests.run({ ...scope, fields: {} }, work);
}

/** Adds fields to every entry the current request logs from here on; outside one, nothing. */
export function logAlso(fields: Record<string, unknown>): void {
  const scope = requests.getStore();
  if (scope !== undefined) Object.assign(scope.fields, fields);
}

export interface LogOptions {
  /**
   * The Google Cloud project, so an entry names its request's trace the way Cloud Logging
   * groups a request's entries under it; undefined off Google Cloud.
   * https://cloud.google.com/logging/docs/structured-logging#special-payload-fields
   */
  readonly traceProject?: string | undefined;
}

/** A log that writes each entry as one line to `write` (stdout in production). */
export function createLog(write: (line: string) => void, options: LogOptions = {}): Log {
  const entry =
    (severity: 'ERROR' | 'WARNING' | 'INFO') =>
    (message: string, fields: Record<string, unknown> = {}): void => {
      const scope = requests.getStore();
      const error = fields.error;
      write(
        `${JSON.stringify(
          {
            severity,
            message,
            ...scope?.fields,
            ...fields,
            // Error Reporting groups an ERROR by the stack it finds in this field.
            ...(severity === 'ERROR' && error instanceof Error ? { stack_trace: error.stack } : {}),
            ...(scope === undefined ? {} : traceFields(scope, options.traceProject)),
          },
          redact,
        )}\n`,
      );
    };
  return { error: entry('ERROR'), warn: entry('WARNING'), info: entry('INFO') };
}

function traceFields(scope: RequestScope, project: string | undefined): Record<string, unknown> {
  return {
    requestId: scope.traceId,
    ...(project === undefined
      ? {}
      : {
          'logging.googleapis.com/trace': `projects/${project}/traces/${scope.traceId}`,
          ...(scope.spanId === undefined ? {} : { 'logging.googleapis.com/spanId': scope.spanId }),
        }),
  };
}

/**
 * Fields whose values are what people typed, or secrets, whatever they hold: written as
 * `[redacted]`. Compared in lower case.
 */
const REDACTED_KEYS = new Set([
  'authorization',
  'cookie',
  'token',
  'accesstoken',
  'refreshtoken',
  'idtoken',
  'password',
  'secret',
  'apikey',
  'email',
  'caption',
  'catchphrase',
  'nickname',
  'text',
  'body',
  'prompt',
  'path',
  'photos',
]);

/** What may hide inside any string, an error's message or stack included, and what replaces it. */
const REDACTED_PATTERNS: readonly (readonly [RegExp, string])[] = [
  [/\beyJ[\w-]+\.[\w-]+\.[\w-]*/g, '[token]'],
  [/\bBearer\s+\S+/gi, 'Bearer [token]'],
  [/\bsb_(?:secret|publishable)_\w+/g, '[key]'],
  [/\bsk-[\w-]{16,}/g, '[key]'],
  // A domain ends in letters, so a package in a stack (`hono@4.13.13`) stays.
  [/[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[a-z]{2,}\b/gi, '[email]'],
  // A photo's path in Storage: the member's folder, then the photo.
  [
    /\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b/gi,
    '[photo]',
  ],
  // A phone's APNs device token.
  [/\b[0-9a-f]{64,}\b/gi, '[device]'],
];

/** `JSON.stringify`'s replacer: describes errors and redacts every field and string it meets. */
function redact(key: string, value: unknown): unknown {
  if (REDACTED_KEYS.has(key.toLowerCase()) && value !== undefined && value !== null) {
    return '[redacted]';
  }
  if (typeof value === 'string') {
    return REDACTED_PATTERNS.reduce((text, [pattern, mark]) => text.replace(pattern, mark), value);
  }
  // `JSON.stringify` drops an Error's message and stack, which are what a log needs.
  return value instanceof Error
    ? { name: value.name, message: value.message, stack: value.stack, cause: value.cause }
    : value;
}
