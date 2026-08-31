import { test } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { gotoChecked, assertNoError, assertLayout, shot } from './lib/helpers';
import { exerciseControls, isUnreachable } from './lib/crawler';

const manifest = path.resolve(process.cwd(), '.artifacts/urls-fo.json');
const urls: string[] = fs.existsSync(manifest) ? JSON.parse(fs.readFileSync(manifest, 'utf-8')) : [];

test.use({ storageState: { cookies: [], origins: [] } });

test.describe('Front Office — parcours complet (toutes les pages découvertes)', () => {
  if (!urls.length) {
    test('manifeste FO présent', () => {
      throw new Error('Aucune URL FO découverte (.artifacts/urls-fo.json vide). Le global-setup a-t-il tourné ?');
    });
  }

  urls.forEach((url, i) => {
    const label = new URL(url).pathname + new URL(url).search;
    test(`FO ${String(i + 1).padStart(2, '0')} · ${label}`, async ({ page }) => {
      if (isUnreachable(url)) {
        test.info().annotations.push({ type: 'env-absent', description: `URL injoignable à la découverte : ${url}` });
        test.skip(true, 'URL injoignable à la découverte');
      }
      const resp = await gotoChecked(page, url);
      await assertNoError(page, resp);
      await assertLayout(page);
      await shot(page, `fo ${label}`);
      await exerciseControls(page);
    });
  });
});
