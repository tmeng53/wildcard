import { randomBytes } from 'node:crypto';

import { createMiddleware } from 'hono/factory';

import { inRequest, type RequestScope } from './log.js';

/** The response header that tells the app, and whoever reads its report, which request it was. */
export const REQUEST_ID_HEADER = 'X-Request-Id';

/**
 * Runs each request in its trace, so every entry it logs carries the trace and Cloud Logging
 * shows them under Cloud Run's own line for the request; the response names it in
 * `X-Request-Id`. Off Cloud Run (no trace header) the request gets a random id.
 */
export function requestTrace() {
  return createMiddleware(async (c, next) => {
    const scope = traceOf(c.req.header('x-cloud-trace-context'), c.req.header('traceparent'));
    await inRequest(scope, async () => {
      await next();
      c.header(REQUEST_ID_HEADER, scope.traceId);
    });
  });
}

/**
 * The trace and span in Google's `X-Cloud-Trace-Context: TRACE/SPAN;o=1` (the span in decimal),
 * else in W3C `traceparent: 00-TRACE-SPAN-FLAGS`. Anything else in them is ignored, since a client
 * can send either.
 * https://cloud.google.com/trace/docs/trace-context
 */
export function traceOf(
  cloudTraceContext: string | undefined,
  traceparent: string | undefined,
): Omit<RequestScope, 'fields'> {
  const google = /^([0-9a-f]{32})(?:\/(\d{1,20}))?(?:;|$)/i.exec(cloudTraceContext ?? '');
  if (google?.[1] !== undefined && !/^0+$/.test(google[1])) {
    return {
      traceId: google[1].toLowerCase(),
      spanId: google[2] === undefined ? undefined : spanHex(google[2]),
    };
  }
  const w3c = /^[0-9a-f]{2}-([0-9a-f]{32})-([0-9a-f]{16})-[0-9a-f]{2}$/i.exec(traceparent ?? '');
  if (w3c?.[1] !== undefined && w3c[2] !== undefined && !/^0+$/.test(w3c[1])) {
    return { traceId: w3c[1].toLowerCase(), spanId: w3c[2].toLowerCase() };
  }
  return { traceId: randomBytes(16).toString('hex'), spanId: undefined };
}

/** Cloud Logging takes a span as 16 hex digits; Google's header sends it in decimal. */
function spanHex(decimal: string): string | undefined {
  const span = BigInt(decimal);
  return span > 0n && span < 2n ** 64n ? span.toString(16).padStart(16, '0') : undefined;
}
