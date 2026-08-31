import { test, expect } from '@playwright/test';
import { gotoChecked, assertNoError, shot, env } from './lib/helpers';

// Login Front Office (mylutece-database) avec un utilisateur de test seedé (voir
// scripts/testenv/seed-fo-user.md). Vérifie l'état connecté (pas seulement l'affichage).
const FO_CONFIGURE = Boolean(process.env.FO_USER && process.env.FO_PASS);

test.use({ storageState: { cookies: [], origins: [] } });

test.describe('Front Office — authentification (mylutece-database)', () => {
  test('login FO avec utilisateur de test', async ({ page }) => {
    if (!FO_CONFIGURE) {
      test.info().annotations.push({
        type: 'env-absent',
        description: 'FO_USER/FO_PASS absents de .env.local — utilisateur FO de test non seedé (scripts/testenv/seed-fo-user.md)',
      });
    }
    test.skip(!FO_CONFIGURE, 'utilisateur FO de test non configuré (FO_USER / FO_PASS)');

    const resp = await gotoChecked(page, 'jsp/site/Portal.jsp?page=mylutece&action=login&auth_provider=mylutece-database');
    await assertNoError(page, resp);

    const identifiant = page.locator('input[name="username"], input[name="login"], input[name="j_username"]').first();
    if ((await identifiant.count()) === 0) {
      test.info().annotations.push({
        type: 'na',
        description: 'aucun formulaire de connexion FO exposé (mylutece-database non assemblé) — authentification FO non mesurable',
      });
      test.skip(true, 'formulaire de connexion FO absent de l’assemblage');
      return;
    }

    await identifiant.fill(env('FO_USER'));
    await page.locator('input[name="password"], input[type="password"], input[name="j_password"]').first().fill(env('FO_PASS'));
    await page.locator('form:has(input[type="password"]) button[type="submit"], form:has(input[type="password"]) input[type="submit"]').first().click();
    await page.waitForLoadState('domcontentloaded').catch(() => {});
    await shot(page, 'fo login result');
    // Effet : session FO ouverte → présence d'un lien de déconnexion ou du nom d'utilisateur, pas de message d'erreur.
    const body = (await page.locator('body').innerText().catch(() => '')) || '';
    expect(/erreur|incorrect|invalide|échou/i.test(body), 'pas de message d’échec de login').toBe(false);
    const loggedIn = await page.locator('a[href*="logout" i], a[href*="doLogout" i], :text("déconnexion")').first().count();
    expect(loggedIn, 'indice de session FO (lien de déconnexion)').toBeGreaterThan(0);
  });
});
