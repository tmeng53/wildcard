/**
 * The trace id Cloud Run's load balancer gives a request, which finds all of its log lines in
 * Cloud Logging: from `X-Cloud-Trace-Context` (`TRACE_ID/SPAN_ID;o=1`), else from W3C
 * `traceparent` (`00-TRACE_ID-SPAN_ID-01`). Undefined for a request without either, such as a
 * local one.
 * https://cloud.google.com/trace/docs/trace-context
 */
export function traceIdOf(header: (name: string) => string | undefined): string | undefined {
  const cloud = /^([0-9a-f]{32})\//i.exec(header('x-cloud-trace-context') ?? '');
  if (cloud?.[1] !== undefined) return cloud[1].toLowerCase();
  const w3c = /^[0-9a-f]{2}-([0-9a-f]{32})-[0-9a-f]{16}-[0-9a-f]{2}$/i.exec(
    header('traceparent') ?? '',
  );
  return w3c?.[1]?.toLowerCase();
}
