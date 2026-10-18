import { defineConfig } from 'vitest/config';

export default defineConfig({
  // Workspace packages resolve to their TypeScript source, so tests need no build.
  resolve: { conditions: ['@wildcard/source'] },
  ssr: { resolve: { conditions: ['@wildcard/source'] } },
  test: {
    include: ['{apps,packages}/*/src/**/*.test.ts'],
    // Tests share one local Supabase.
    fileParallelism: false,
  },
});
