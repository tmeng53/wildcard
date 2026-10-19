// @ts-check
// From sponge-ai-lab/engineering-skills (verification skill, templates/eslint.config.js),
// with `@project` renamed to `@wildcard`. The errors rule covers apps too, since the server
// defines errors of its own.
import eslint from '@eslint/js';
import prettier from 'eslint-config-prettier/flat';
import { defineConfig, globalIgnores } from 'eslint/config';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import vitest from '@vitest/eslint-plugin';

export default defineConfig(
  // tables.ts files are written by `pnpm db-types` from the migrations.
  globalIgnores(['**/dist/', '**/coverage/', '**/src/adapters/tables.ts']),

  { linterOptions: { reportUnusedDisableDirectives: 'error' } },

  eslint.configs.recommended,
  tseslint.configs.strictTypeChecked,
  tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      globals: globals.node,
      parserOptions: {
        // Each package has a src project (tsconfig.json) and a test project
        // (tsconfig.test.json); typed linting needs both.
        project: ['./{packages,apps}/*/tsconfig.json', './{packages,apps}/*/tsconfig.test.json'],
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/consistent-type-exports': 'error',
      '@typescript-eslint/no-import-type-side-effects': 'error',

      // Rules below encode pstack's type-system-discipline and
      // typescript-best-practices skills, so a reviewer doesn't have to.

      // No `as` casts: parse with a schema, narrow, or use `satisfies`.
      // `as const` is still allowed.
      '@typescript-eslint/consistent-type-assertions': ['error', { assertionStyle: 'never' }],
      // A `default` arm must not hide a new union member from the compiler.
      '@typescript-eslint/switch-exhaustiveness-check': [
        'error',
        { considerDefaultExhaustiveForUnions: false, requireDefaultForNonUnion: true },
      ],
      // Pass an object instead of a third positional argument.
      '@typescript-eslint/max-params': ['error', { max: 2 }],
      // Shipped code logs through a structured logger, never the console.
      'no-console': 'error',
    },
  },

  // Tests observe behavior: see pstack's test-behavior-not-implementation skill.
  {
    files: ['**/*.{test,spec}.{ts,tsx,mts}'],
    plugins: { vitest },
    rules: {
      ...vitest.configs.recommended.rules,
      'vitest/expect-expect': 'error',
      'vitest/no-conditional-expect': 'error',
      'vitest/no-focused-tests': 'error',
      'vitest/no-disabled-tests': 'error',
      'vitest/no-standalone-expect': 'error',
      // These matchers pass for almost any value, so they can't catch a defect.
      // Assert the literal value or observable effect instead.
      'vitest/no-restricted-matchers': [
        'error',
        {
          toBeDefined: 'Assert the literal expected value instead.',
          toBeTruthy: 'Assert the literal expected value instead.',
          toBeFalsy: 'Assert the literal expected value instead.',
          toBeInstanceOf: 'Assert the observable fields or message instead.',
          'not.toThrow': 'Assert the returned value instead.',
          toHaveBeenCalled: 'Assert the payload it received or the resulting state instead.',
          'not.toHaveBeenCalled': 'Assert the resulting state instead.',
        },
      ],
      // Don't mock what you can run. Disable per line, with a reason, for real
      // external systems (e.g. a third-party API).
      'vitest/no-restricted-vi-methods': [
        'error',
        { mock: 'Run the real module; mock only systems you cannot run locally.' },
      ],
    },
  },

  // Plain JS config files are not part of any TS project. They follow the same no-console rule:
  // exempt a specific file here only if it truly needs the console.
  {
    files: ['**/*.js', '**/*.mjs', '**/*.cjs'],
    extends: [tseslint.configs.disableTypeChecked],
  },

  // Errors a caller can act on extend AppError from @wildcard/errors, so apps can
  // answer any of them the same way. See .claude/skills/errors. Exempt: the base itself.
  {
    files: ['{packages,apps}/*/src/**/*.ts'],
    ignores: ['**/*.test.ts', 'packages/errors/**'],
    rules: {
      'no-restricted-syntax': [
        'error',
        {
          selector: ':matches(ClassDeclaration, ClassExpression)[superClass.name="Error"]',
          message:
            'Extend AppError from @wildcard/errors, not Error, so apps can map it. See .claude/skills/errors.',
        },
      ],
    },
  },

  // Must stay last: turns off rules that conflict with Prettier.
  prettier,
);
