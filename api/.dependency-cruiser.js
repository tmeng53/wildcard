// Package boundaries for the TypeScript workspace. Run with `pnpm boundaries`.
//
// From sponge-ai-lab/engineering-skills (module-structure skill), with `project` renamed to
// `wildcard` (the package.json key and the `@wildcard/source` export condition).
//
// The idea: every package under packages/ or apps/ is a black box with one
// door, the entry point in its package.json `exports`. Rules below keep it that
// way. Paths are relative to the repo root; `$1`/`$2` in a `to` rule refer to
// the capture groups of the matching `from` path.

import { existsSync, readdirSync, readFileSync } from 'node:fs';

/** A file inside a workspace package: group 1 = packages|apps, group 2 = folder. */
const IN_PACKAGE = '^(packages|apps)/([^/]+)/';

// Every package declares what kind it is in its package.json: `"wildcard": { "kind": "module" }`.
// The kinds and the rules between them are explained in .claude/skills/module-structure.
const KINDS = ['contract', 'module', 'flow', 'adapter', 'app', 'supporting'];
const ROOT = new URL('.', import.meta.url);
const byKind = Object.fromEntries(KINDS.map((kind) => [kind, []]));
const undeclared = [];
for (const group of ['packages', 'apps']) {
  const dir = new URL(`${group}/`, ROOT);
  if (!existsSync(dir)) continue;
  for (const name of readdirSync(dir)) {
    const manifest = new URL(`${group}/${name}/package.json`, ROOT);
    if (!existsSync(manifest)) continue;
    const kind = JSON.parse(readFileSync(manifest, 'utf8')).wildcard?.kind;
    if (KINDS.includes(kind)) byKind[kind].push(`${group}/${name}`);
    else undeclared.push(`${group}/${name}`);
  }
}
if (undeclared.length > 0) {
  throw new Error(
    `Declare a kind in package.json ("wildcard": { "kind": "${KINDS.join(' | ')}" }) for: ` +
      `${undeclared.join(', ')}. See .claude/skills/module-structure.`,
  );
}

/** Matches any file in a package of these kinds; never matches when there are none. */
const kindPath = (...kinds) => {
  const dirs = kinds.flatMap((kind) => byKind[kind]);
  return dirs.length > 0 ? `^(${dirs.join('|')})/` : '^$.';
};
/** Production code (src/, not tests) in packages of these kinds, with IN_PACKAGE's groups. */
const productionIn = (...kinds) => {
  const dirs = kinds.flatMap((kind) => byKind[kind]).map((dir) => dir.split('/')[1]);
  return {
    path: dirs.length > 0 ? `^(packages|apps)/(${dirs.join('|')})/src/` : '^$.',
    pathNot: '\\.test\\.ts$',
  };
};

/** @type {import('dependency-cruiser').IConfiguration} */
export default {
  forbidden: [
    {
      name: 'no-circular',
      severity: 'error',
      comment: 'Circular dependencies make modules impossible to understand or test in isolation.',
      from: {},
      to: { circular: true },
    },
    {
      name: 'no-relative-import-across-packages',
      severity: 'error',
      comment:
        'Import another package by its name (e.g. `@wildcard/errors`), never with a relative path ' +
        'into its folder.',
      from: { path: IN_PACKAGE },
      to: { dependencyTypes: ['local'], pathNot: '^$1/$2/' },
    },
    {
      name: 'only-public-entry-points',
      severity: 'error',
      comment:
        "Another package may only be reached through its public entry point (`exports['.']`, " +
        'which resolves to src/index.ts). Deep imports into its internals are forbidden.',
      from: { path: IN_PACKAGE },
      to: {
        path: '^(packages|apps)/[^/]+/',
        pathNot: ['^$1/$2/', '^(packages|apps)/[^/]+/src/index\\.ts$'],
      },
    },
    {
      name: 'core-depends-on-no-workspace-package',
      severity: 'error',
      comment:
        'packages/core is the shared contract: everything may depend on it, it depends on no ' +
        'other workspace package.',
      from: { path: '^packages/core/' },
      to: { path: '^(packages|apps)/', pathNot: '^packages/core/' },
    },
    {
      name: 'modules-import-only-the-contract',
      severity: 'error',
      comment:
        'A module never imports another module, a flow, an adapter or an app. Anything that ' +
        'spans modules goes in a flow, or reacts to a contract event.',
      from: productionIn('module'),
      to: { path: kindPath('module', 'flow', 'adapter', 'app'), pathNot: '^$1/$2/' },
    },
    {
      name: 'flows-do-not-import-adapters',
      severity: 'error',
      comment:
        'A flow calls modules and the contract. Adapters are wired in by the app that runs it, ' +
        'so the flow stays testable with fakes.',
      from: productionIn('flow'),
      to: { path: kindPath('adapter', 'app') },
    },
    {
      name: 'adapters-implement-a-module-port',
      severity: 'error',
      comment:
        'An adapter imports the contract and the module whose port it implements, never a flow, ' +
        'an app or another adapter.',
      from: productionIn('adapter'),
      to: { path: kindPath('flow', 'app', 'adapter'), pathNot: '^$1/$2/' },
    },
    {
      name: 'supporting-packages-stay-below-flows',
      severity: 'error',
      comment:
        'A supporting package (shared helpers, test kit, SDK) never imports a flow, an adapter ' +
        'or an app.',
      from: productionIn('supporting'),
      to: { path: kindPath('flow', 'adapter', 'app') },
    },
    {
      name: 'nothing-imports-an-app',
      severity: 'error',
      comment: 'Apps are the end of the graph: they are deployed, never imported.',
      from: { path: IN_PACKAGE },
      to: { path: kindPath('app'), pathNot: '^$1/$2/' },
    },
    {
      // Wildcard's own rule (Tracy, 2026-10-18): Auth, Storage and Postgres stay swappable, so
      // only the composition root (main.ts) picks a provider's adapter; everything else uses the
      // interfaces in src/ports.ts.
      name: 'adapters-only-in-the-composition-root',
      severity: 'error',
      comment:
        'Only main.ts (and tests) may import from src/adapters/. Depend on the port in ' +
        'src/ports.ts instead, so a provider can be swapped by writing a new adapter.',
      from: {
        path: '^apps/[^/]+/src/',
        pathNot: ['^apps/[^/]+/src/(main\\.ts$|adapters/)', '\\.test\\.ts$'],
      },
      to: { path: '^apps/[^/]+/src/adapters/' },
    },
    {
      name: 'provider-sdks-only-in-adapters',
      severity: 'error',
      comment:
        "Only src/adapters/ may import a provider's library (pg, @supabase/*). Routes reach " +
        'providers through the ports in src/ports.ts, so swapping a provider touches one adapter.',
      from: { path: '^apps/[^/]+/src/', pathNot: ['^apps/[^/]+/src/adapters/', '\\.test\\.ts$'] },
      to: { path: '(^|/)node_modules/(pg|@supabase/[^/]+)/' },
    },
    {
      name: 'no-dev-dependencies-in-src',
      severity: 'error',
      comment:
        'Production code may not import a devDependency: it would be missing at runtime. ' +
        'Tests (*.test.ts) are exempt.',
      from: { path: `${IN_PACKAGE}src/`, pathNot: '\\.test\\.ts$' },
      to: { dependencyTypes: ['npm-dev'] },
    },
    {
      name: 'no-undeclared-dependencies',
      severity: 'error',
      comment:
        'Every package must list what it imports in its own package.json, even if it happens to ' +
        'resolve from the workspace root.',
      from: { path: IN_PACKAGE },
      to: { dependencyTypes: ['npm-no-pkg', 'npm-unknown'] },
    },
    {
      name: 'not-to-unresolvable',
      severity: 'error',
      comment:
        "This import can't be resolved: a typo, a missing dependency, or a deep import that the " +
        "target package's `exports` doesn't allow.",
      from: {},
      to: { couldNotResolve: true },
    },
  ],

  options: {
    doNotFollow: { path: 'node_modules' },
    exclude: { path: '^(packages|apps)/[^/]+/dist/' },
    // Count `import type` too: type-only coupling is still coupling.
    tsPreCompilationDeps: true,
    tsConfig: { fileName: 'tsconfig.base.json' },
    enhancedResolveOptions: {
      exportsFields: ['exports'],
      // `@wildcard/source` is a custom export condition each workspace package
      // declares, pointing at src/index.ts, so the boundary check works on
      // source without a build. TypeScript and Node ignore it.
      conditionNames: ['@wildcard/source', 'import', 'types', 'node', 'default'],
      extensions: ['.ts', '.js', '.json'],
      mainFields: ['types', 'main'],
    },
    skipAnalysisNotInRules: true,
  },
};
