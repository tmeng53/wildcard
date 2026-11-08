import { describe, expect, it } from 'vitest';

import { IssueTrackerUnavailableError } from '../errors.js';
import { createGitHubIssueTracker } from './github-issues.js';

/** A fetch that answers each call in turn and keeps what it was asked. */
function fetchAnswering(...answers: Response[]) {
  const calls: { method: string; url: string; body: unknown; auth: string | null }[] = [];
  const fake: typeof fetch = (input, init) => {
    const headers = new Headers(init?.headers);
    calls.push({
      method: init?.method ?? 'GET',
      url: input instanceof Request ? input.url : input instanceof URL ? input.href : input,
      body: typeof init?.body === 'string' ? JSON.parse(init.body) : undefined,
      auth: headers.get('authorization'),
    });
    const answer = answers.shift();
    return answer === undefined ? Promise.reject(new Error('no answer')) : Promise.resolve(answer);
  };
  return { fake, calls };
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

describe('the GitHub issue tracker', () => {
  it('commits each attachment, then opens the issue showing them', async () => {
    const { fake, calls } = fetchAnswering(
      json(201, {}),
      // Already there from a try that stopped before the issue.
      json(422, { message: 'sha wasn’t supplied' }),
      json(201, { number: 7, html_url: 'https://github.com/o/r/issues/7' }),
    );
    const tracker = createGitHubIssueTracker({ repo: 'o/r', token: 'secret', fetch: fake });
    const issue = await tracker.open({
      title: 'Problem: hi',
      body: 'Look:\n{{attachment:a.jpg}}\n{{attachment:b.png}}',
      labels: ['new'],
      folder: 'feedback/app-1',
      attachments: [
        { name: 'a.jpg', bytes: new Uint8Array([1, 2]) },
        { name: 'b.png', bytes: new Uint8Array([3]) },
      ],
    });
    expect(issue).toStrictEqual({ number: 7, url: 'https://github.com/o/r/issues/7' });
    expect(calls.map(({ method, url, auth }) => [method, url, auth])).toStrictEqual([
      ['PUT', 'https://api.github.com/repos/o/r/contents/feedback/app-1/a.jpg', 'Bearer secret'],
      ['PUT', 'https://api.github.com/repos/o/r/contents/feedback/app-1/b.png', 'Bearer secret'],
      ['POST', 'https://api.github.com/repos/o/r/issues', 'Bearer secret'],
    ]);
    expect(calls[0]?.body).toStrictEqual({
      message: 'Add feedback/app-1/a.jpg',
      content: 'AQI=',
    });
    expect(calls[2]?.body).toStrictEqual({
      title: 'Problem: hi',
      body:
        'Look:\n![a.jpg](https://github.com/o/r/blob/main/feedback/app-1/a.jpg?raw=true)\n' +
        '![b.png](https://github.com/o/r/blob/main/feedback/app-1/b.png?raw=true)',
      labels: ['new'],
    });
  });

  it('fails as unavailable when GitHub refuses or can’t be reached', async () => {
    const refused = createGitHubIssueTracker({
      repo: 'o/r',
      token: 'secret',
      fetch: fetchAnswering(json(401, { message: 'Bad credentials' })).fake,
    });
    const unreachable = createGitHubIssueTracker({
      repo: 'o/r',
      token: 'secret',
      fetch: fetchAnswering().fake,
    });
    const issue = { title: 't', body: 'b', labels: [], folder: 'f', attachments: [] };
    await expect(refused.open(issue)).rejects.toBeInstanceOf(IssueTrackerUnavailableError);
    await expect(unreachable.open(issue)).rejects.toBeInstanceOf(IssueTrackerUnavailableError);
  });
});
