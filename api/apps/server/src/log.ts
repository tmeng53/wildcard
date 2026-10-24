import type { ErrorReports } from './ports.js';

/**
 * Structured logs: one JSON object per line on stdout, in the shape Cloud Run's logging reads
 * (`severity`, `message`, then any fields). Never the console.
 * https://cloud.google.com/run/docs/logging#writing_structured_logs
 */
export interface Log {
  error(message: string, fields?: Record<string, unknown>): void;
  warn(message: string, fields?: Record<string, unknown>): void;
  info(message: string, fields?: Record<string, unknown>): void;
}

/** A log that writes each entry as one line to `write` (stdout in production). */
export function createLog(write: (line: string) => void): Log {
  const entry =
    (severity: 'ERROR' | 'WARNING' | 'INFO') =>
    (message: string, fields: Record<string, unknown> = {}): void => {
      write(`${JSON.stringify({ severity, message, ...fields }, describeErrors)}\n`);
    };
  return { error: entry('ERROR'), warn: entry('WARNING'), info: entry('INFO') };
}

/** `JSON.stringify` drops an Error's message and stack, which are what a log needs. */
function describeErrors(_key: string, value: unknown): unknown {
  return value instanceof Error
    ? { name: value.name, message: value.message, stack: value.stack, cause: value.cause }
    : value;
}

/**
 * A log whose errors also go to `reports`, so every failure the server logs as an error is
 * reported without each caller knowing about it. Only the message and the fields a report may
 * carry go (`method`, `route`, `traceId`): never ids, paths or anything else a caller logged.
 * An error entry without an `error` field is reported as an Error of its message.
 */
export function reportingErrors(log: Log, reports: ErrorReports): Log {
  return {
    ...log,
    error(message, fields = {}) {
      log.error(message, fields);
      const text = (key: string) => (typeof fields[key] === 'string' ? fields[key] : undefined);
      reports.report(fields.error ?? new Error(message), {
        message,
        method: text('method'),
        route: text('route'),
        traceId: text('traceId'),
      });
    },
  };
}
