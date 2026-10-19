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
