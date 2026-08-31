import { test } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { gotoChecked, assertAuthenticated, assertNoError, assertLayout, shot } from './lib/helpers';
import { exerciseControls, isUnreachable, BoFeature } from './lib/crawler';

const manifest = path.resolve(process.cwd(), '.artifacts/urls-bo.json');
const features: BoFeature[] = fs.existsSync(manifest) ? JSON.parse(fs.readFileSync(manifest, 'utf-8')) : [];

// Utilise la session admin authentifiée (storageState par défaut de la config).
test.describe('Back Office — parcours complet (fonctionnalités admin découvertes)', () => {
  if (!features.length) {
    test('manifeste BO présent', () => {
      throw new Error('Aucune fonctionnalité BO découverte (.artifacts/urls-bo.json vide). Login global-setup OK ?');
    });
  }

  features.forEach((feat, i) => {
    const label = feat.label || new URL(feat.url).pathname;
    test(`BO ${String(i + 1).padStart(2, '0')} · ${label}`, async ({ page }) => {
      if (isUnreachable(feat)) {
        test.info().annotations.push({ type: 'env-absent', description: `URL injoignable à la découverte : ${feat.url}` });
        test.skip(true, 'URL injoignable à la découverte');
      }
      const resp = await gotoChecked(page, feat.url);
      await assertNoError(page, resp);
      await assertAuthenticated(page);
      await assertLayout(page);
      await shot(page, `bo ${label}`);
      await exerciseControls(page);
    });
  });
});
