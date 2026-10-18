import type { App } from './app.js';

/** The OpenAPI 3.1 document for every route, as committed in `openapi.json`. */
export function openApiJson(app: App): string {
  const document = app.getOpenAPI31Document({
    openapi: '3.1.0',
    info: {
      title: 'Wildcard API',
      version: '1',
      description:
        'The only way into Wildcard’s data. Every JSON body carries a top-level `version`; ' +
        'every failure is an RFC 9457 problem with a stable `reason`.',
    },
  });
  return `${JSON.stringify(document, null, 2)}\n`;
}
