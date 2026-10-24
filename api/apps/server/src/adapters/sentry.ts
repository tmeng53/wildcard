import * as Sentry from '@sentry/node';

import type { ErrorReports } from '../ports.js';

/**
 * Error reports through Sentry. Only the integrations named here run: none of the SDK's defaults,
 * which would trace HTTP, the database and the AI providers' SDKs and record what passes through
 * them. Crashes (an uncaught exception or unhandled rejection) are reported too, then the process
 * exits as Node would.
 * https://docs.sentry.io/platforms/javascript/guides/node/configuration/integrations/
 */
export function createSentryErrorReports(options: {
  readonly dsn: string;
  /** The deployed revision, which Sentry shows as the release. */
  readonly release: string | undefined;
  /**
   * Masks what may hide in an error's message (an email, a token, a photo's path), as the log
   * does, before a report leaves.
   */
  readonly redact: (text: string) => string;
  /** For tests: where envelopes go instead of Sentry's servers. */
  readonly transport?: Sentry.NodeOptions['transport'];
}): ErrorReports {
  // The log keeps ids (a member's, a squad's) to find what failed; a report, which leaves our
  // project, names none.
  const mask = (text: string) =>
    options.redact(text).replace(/\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b/gi, '[id]');
  Sentry.initWithoutDefaultIntegrations({
    dsn: options.dsn,
    release: options.release,
    environment: 'production',
    // Collect nothing about people or what requests carry, whatever an integration could add.
    dataCollection: {
      userInfo: false,
      cookies: false,
      httpHeaders: false,
      httpBodies: [],
      urlQueryParams: false,
      graphQL: { document: false, variables: false },
      genAI: { inputs: false, outputs: false },
      databaseQueryData: false,
      queues: false,
      stackFrameVariables: false,
    },
    maxBreadcrumbs: 0,
    integrations: [
      Sentry.linkedErrorsIntegration(),
      Sentry.dedupeIntegration(),
      Sentry.onUncaughtExceptionIntegration(),
      Sentry.onUnhandledRejectionIntegration(),
    ],
    // Drop it again on the way out, in case a later SDK adds it by default, and mask what an
    // error's message may carry.
    beforeSend: (event) => {
      delete event.user;
      delete event.request;
      for (const exception of event.exception?.values ?? []) {
        if (exception.value !== undefined) exception.value = mask(exception.value);
      }
      if (event.message !== undefined) event.message = mask(event.message);
      return event;
    },
    ...(options.transport === undefined ? {} : { transport: options.transport }),
  });
  return {
    report: (error, context) => {
      Sentry.withScope((scope) => {
        scope.setTag('log_message', context.message);
        if (context.method !== undefined) scope.setTag('method', context.method);
        if (context.route !== undefined) scope.setTag('route', context.route);
        if (context.traceId !== undefined) scope.setTag('request_id', context.traceId);
        Sentry.captureException(error);
      });
    },
    flush: async (timeoutMs) => {
      await Sentry.flush(timeoutMs);
    },
  };
}
