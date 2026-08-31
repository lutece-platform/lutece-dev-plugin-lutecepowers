import { test, expect } from '@playwright/test';
import { gotoChecked, assertNoError, shot, env, normalizeUrl } from './lib/helpers';

const PREFIXE_SITE = new URL(env('BASE_URL')).href.replace(/\/*$/, '/');
const MAX_ENTREES = 5;

test.use({ storageState: { cookies: [], origins: [] } });

test.describe('Front Office — fonctionnel', () => {
  test('Recherche : la barre de recherche de la page d’accueil mène à une page saine', async ({ page }) => {
    const resp = await gotoChecked(page, '');
    await assertNoError(page, resp);

    const searchBox = page
      .locator(
        'input[type="search"]:visible, input[name="query"]:visible, input[name="q"]:visible, input[placeholder*="echerch" i]:visible',
      )
      .first();
    if ((await searchBox.count()) === 0) {
      test.info().annotations.push({
        type: 'na',
        description: 'aucune barre de recherche exposée sur la page d’accueil — recherche FO non mesurable',
      });
      test.skip(true, 'aucune barre de recherche sur la page d’accueil');
      return;
    }

    await searchBox.fill('lutece');
    await searchBox.press('Enter');
    await page.waitForLoadState('domcontentloaded');
    await assertNoError(page);
    await shot(page, 'fo recherche');
  });

  test('Navigation : chaque entrée de l’en-tête mène à une page saine', async ({ page }) => {
    const resp = await gotoChecked(page, '');
    await assertNoError(page, resp);
    await shot(page, 'fo accueil');

    const liens = await page.locator('header a[href], nav a[href]').evaluateAll((noeuds) =>
      noeuds.map((a) => ({
        href: a.getAttribute('href') || '',
        resolu: (a as HTMLAnchorElement).href || '',
      })),
    );

    const entrees = [
      ...new Set(
        liens
          .filter(({ href }) => href !== '' && !/^(mailto:|tel:|javascript:|#)/i.test(href))
          .map(({ resolu }) => normalizeUrl(resolu))
          .filter((url) => url.startsWith(PREFIXE_SITE) && url !== PREFIXE_SITE),
      ),
    ].slice(0, MAX_ENTREES);

    expect(entrees.length, 'entrées de navigation trouvées').toBeGreaterThan(0);

    for (const url of entrees) {
      const reponse = await gotoChecked(page, url);
      await assertNoError(page, reponse);
      expect(page.url(), `l’entrée ${url} reste sous le site`).toContain(PREFIXE_SITE);
    }
    await shot(page, 'fo navigation entete');
  });

  test('Contact : formulaire du socle s’il est assemblé, sinon dégradation propre', async ({ page }) => {
    const resp = await gotoChecked(page, 'jsp/site/Portal.jsp?page=contact&view=viewContactPage&id_contact_list=1');

    const nom = page.locator('input[name="visitor_last_name"]');
    if (await nom.count()) {
      await assertNoError(page, resp);
      await nom.fill('E2ETest');
      await page.locator('input[name="visitor_first_name"]').fill('Playwright');
      await page.locator('input[name="visitor_email"]').fill('e2e@example.invalid');
      const obj = page.locator('input[name="message_object"]');
      if (await obj.count()) await obj.fill('Démonstration e2e — ne pas traiter');
      await page
        .locator('textarea[name="message"], [name="message"]')
        .first()
        .fill('Ceci est un test end-to-end automatisé. Le formulaire est rempli mais volontairement NON soumis.');
      await shot(page, 'fo contact rempli (non soumis)');
      await expect(page.locator('button[type="submit"], input[type="submit"]').first()).toBeVisible();
      return;
    }

    test.info().annotations.push({
      type: 'na',
      description: `formulaire de contact du socle absent (plugin-contact non assemblé), statut ${resp ? resp.status() : 'inconnu'} — dégradation propre vérifiée à la place`,
    });
    if (resp) expect(resp.status(), 'la sollicitation contact dégrade sans erreur serveur').toBeLessThan(500);

    const accueil = await gotoChecked(page, '');
    await assertNoError(page, accueil);
    const mailtos = page.locator('a[href^="mailto:"]');
    if ((await mailtos.count()) === 0) {
      test.info().annotations.push({
        type: 'na',
        description: 'aucune adresse mailto: exposée — pas de moyen de contact alternatif à mesurer',
      });
      return;
    }
    const adresse = await mailtos.first().getAttribute('href');
    expect(adresse, 'adresse de contact exploitable').toMatch(/^mailto:[^@\s]+@[\w.-]+\.[a-z]{2,}$/i);
    await shot(page, 'fo contact adresse');
  });
});
