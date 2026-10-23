// From sponge-ai-lab/engineering-skills (verification skill, templates/eslint.config.js), cut down
// for plain JavaScript: the site ships its scripts as they are, with no build step.
import eslint from '@eslint/js';
import prettier from 'eslint-config-prettier/flat';
import { defineConfig, globalIgnores } from 'eslint/config';
import globals from 'globals';

export default defineConfig(
  // Written by `pnpm generate` from the app's art.
  globalIgnores([
    'public/home/characters.js',
    'public/join/characters.js',
    'test-results/',
    'playwright-report/',
  ]),

  { linterOptions: { reportUnusedDisableDirectives: 'error' } },

  eslint.configs.recommended,
  {
    files: ['public/**/*.js'],
    languageOptions: { sourceType: 'script', globals: globals.browser },
  },
  // The character modules are shared with scripts/generate.mjs; the invite page loads them as modules.
  {
    files: ['public/character/*.js', 'public/join/join.js'],
    languageOptions: { sourceType: 'module' },
  },
  {
    files: ['scripts/**/*.mjs', 'tests/**/*.js', '*.js'],
    languageOptions: { globals: globals.node },
  },
  // Playwright runs the callbacks passed to page.evaluate in the browser.
  {
    files: ['tests/**/*.js'],
    languageOptions: { globals: { ...globals.node, ...globals.browser } },
  },

  // Must stay last: turns off rules that conflict with Prettier.
  prettier,
);
