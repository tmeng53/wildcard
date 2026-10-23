// The home page's layout and behavior tests, in Chromium against scripts/serve.mjs.
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: 'tests',
  forbidOnly: !!process.env.CI,
  reporter: 'list',
  use: { baseURL: 'http://localhost:4322', ...devices['Desktop Chrome'] },
  webServer: {
    command: 'node scripts/serve.mjs 4322',
    url: 'http://localhost:4322',
    reuseExistingServer: false,
  },
});
