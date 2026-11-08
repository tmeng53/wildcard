import { z } from 'zod';

import { IssueTrackerUnavailableError } from '../errors.js';
import type { IssueTracker } from '../ports.js';

const API = 'https://api.github.com';

/** What GitHub answers an issue's creation with, the fields read here. */
const OpenedIssue = z.object({ number: z.int().positive(), html_url: z.url() });

/**
 * The issue tracker on a GitHub repository (members' feedback goes to a private one), through
 * its REST API with a fine-grained token that may write the repository's issues and contents.
 * Attachments are committed to the default branch, `main`, and shown in the issue from there.
 * https://docs.github.com/en/rest/issues/issues#create-an-issue
 * https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents
 */
export function createGitHubIssueTracker(options: {
  /** `owner/name`. */
  readonly repo: string;
  readonly token: string;
  readonly fetch?: typeof fetch;
}): IssueTracker {
  const send = options.fetch ?? fetch;

  async function call({
    method,
    path,
    body,
  }: {
    readonly method: string;
    readonly path: string;
    readonly body: unknown;
  }): Promise<Response> {
    try {
      return await send(`${API}/repos/${options.repo}${path}`, {
        method,
        headers: {
          accept: 'application/vnd.github+json',
          authorization: `Bearer ${options.token}`,
          'content-type': 'application/json',
          'user-agent': 'wildcard-api',
          'x-github-api-version': '2022-11-28',
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(20_000),
      });
    } catch (error) {
      throw new IssueTrackerUnavailableError(`GitHub ${method} ${path} failed`, { cause: error });
    }
  }

  return {
    async open({ title, body, labels, folder, attachments }) {
      let text = body;
      for (const { name, bytes } of attachments) {
        const path = `${folder}/${name}`;
        const response = await call({
          method: 'PUT',
          path: `/contents/${path}`,
          body: { message: `Add ${path}`, content: Buffer.from(bytes).toString('base64') },
        });
        // 422: the file is there already, from a try that stopped before opening the issue.
        if (!response.ok && response.status !== 422) {
          throw new IssueTrackerUnavailableError(
            `GitHub refused ${path} (${String(response.status)})`,
          );
        }
        const image = `![${name}](https://github.com/${options.repo}/blob/main/${path}?raw=true)`;
        text = text.replaceAll(`{{attachment:${name}}}`, image);
      }
      const response = await call({
        method: 'POST',
        path: '/issues',
        body: { title, body: text, labels },
      });
      if (!response.ok) {
        throw new IssueTrackerUnavailableError(
          `GitHub refused the issue (${String(response.status)})`,
        );
      }
      const issue = OpenedIssue.safeParse(await response.json().catch(() => undefined));
      if (!issue.success)
        throw new IssueTrackerUnavailableError('GitHub answered without an issue');
      return { number: issue.data.number, url: issue.data.html_url };
    },
  };
}
