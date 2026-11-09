import { AppCopyChange, MemberId, type AppCopyAdmin } from '@wildcard/app-copy';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The app's copy: lines put over the words its String Catalog ships with, by key. The public
// catalog serves them, so a phone shows a change from its first launch after its next catalog
// read, with no app release; each change is logged with the whole new copy.

interface AppCopyToolDependencies {
  readonly copy: AppCopyAdmin;
}

/** `get_app_copy`: every line put over the app's own, by key. */
export function getAppCopy({ copy }: AppCopyToolDependencies) {
  return adminTool({
    name: 'get_app_copy',
    title: 'Read the app copy put over the app’s',
    description:
      'Shows every line put over the words the app ships with, by its String Catalog key (the ' +
      'Simplified Chinese source line in the app’s Localizable.xcstrings files), in the ' +
      'languages it changes. Any other key shows the build’s own words.',
    changes: false,
    input: z.strictObject({}),
    run: async () => copy.current(),
  });
}

/** `change_app_copy`: puts lines and takes keys back. */
export function changeAppCopy({ copy }: AppCopyToolDependencies) {
  return adminTool({
    name: 'change_app_copy',
    title: 'Change the app copy',
    description:
      'Changes a line the app shows (a title, a button, a push) without an app release: `put` ' +
      'gives words by String Catalog key, the exact key in the app’s Localizable.xcstrings ' +
      '(its Simplified Chinese source, placeholders such as %lld and %@ included), in any of ' +
      'zhHans, en and zhHant (a language left out keeps the build’s words); each replaces what ' +
      'its key had. The words must keep the key’s placeholders, the same kinds, in any order ' +
      'with explicit positions (%2$lld). `takeBack` returns keys to the build’s words. A key ' +
      'the app doesn’t have changes nothing. Phones use the change from their first launch ' +
      'after reading the catalog (about a minute), in the app and in pushes. Returns the copy now.',
    changes: true,
    input: AppCopyChange,
    run: async (change, { admin }) => copy.change(change, MemberId.parse(admin)),
  });
}

export const appCopyTools = (deps: AppCopyToolDependencies) => [
  getAppCopy(deps),
  changeAppCopy(deps),
];
