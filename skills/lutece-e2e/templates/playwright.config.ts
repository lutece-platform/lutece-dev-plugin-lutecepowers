import { defineConfig } from '@playwright/test';
import * as dotenv from 'dotenv';

// Charge la conf locale (URL, identifiants, DB). Non versionné — voir .env.local.example.
dotenv.config({ path: '.env.local' });

const baseUrl = process.env.BASE_URL;
if (!baseUrl) throw new Error('BASE_URL absente : .env.local non chargé ?');

export const BASE_URL: string = baseUrl;

export default defineConfig({
  testDir: './tests',
  globalSetup: './tests/global-setup.ts',
  globalTeardown: './tests/global-teardown.ts',
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [
    ['list'],
    ['./reporter/pdf-reporter.ts', { outputDir: 'report' }],
  ],
  use: {
    baseURL: BASE_URL,
    storageState: 'storageState.json',
    headless: process.env.HEADLESS === '1',
    ignoreHTTPSErrors: true,
    viewport: { width: 1440, height: 900 },
    locale: 'fr-FR',
    timezoneId: 'Europe/Paris',
    extraHTTPHeaders: { 'Accept-Language': 'fr-FR,fr;q=0.9' },
    screenshot: 'on',
    video: 'on',
    trace: 'on',
    actionTimeout: 15_000,
    navigationTimeout: 30_000,
    launchOptions: {
      slowMo: Number(process.env.SLOWMO || (process.env.HEADLESS === '1' ? 0 : 350)),
      args: ['--ignore-certificate-errors'],
    },
  },
  projects: [
    { name: 'chromium', use: { browserName: 'chromium' } },
  ],
});
