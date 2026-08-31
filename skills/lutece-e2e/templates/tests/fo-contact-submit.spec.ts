import { test, expect } from '@playwright/test';
import { clearMails, waitForMail, mailhogUp } from './lib/mail';
import { gotoChecked, assertNoError } from './lib/helpers';

// Flux CONTACT soumis pour de vrai → mail vérifié dans MailHog.
// Nécessite l'env de test : MailHog (mail) + le CAPTCHA neutralisé (WireMock CaptchEtat « valide »,
// OU captcha désactivé en profil e2e). Voir scripts/testenv/REGISTRY.md.
test.use({ storageState: { cookies: [], origins: [] } });

test.describe('Front Office — contact soumis (env de test) → mail vérifié', () => {
  test('remplir + soumettre le contact → mail capturé', async ({ page }) => {
    const mailDispo = await mailhogUp();
    if (!mailDispo) {
      test.info().annotations.push({
        type: 'env-absent',
        description: 'MailHog injoignable — env de test non démarré (scripts/testenv/testenv.sh up mail)',
      });
    }
    test.skip(!mailDispo, 'MailHog absent — env de test non démarré (scripts/testenv/testenv.sh up mail)');

    await clearMails();
    const resp = await gotoChecked(page, 'jsp/site/Portal.jsp?page=contact&view=viewContactPage&id_contact_list=1');
    await assertNoError(page, resp);

    const nom = page.locator('input[name="visitor_last_name"]');
    if ((await nom.count()) === 0) {
      test.info().annotations.push({
        type: 'na',
        description: 'formulaire de contact du socle absent (plugin-contact non assemblé) — flux de soumission non mesurable',
      });
      test.skip(true, 'formulaire de contact absent de l’assemblage');
      return;
    }

    const formulaire = page.locator('form:has(input[name="visitor_last_name"])').first();
    await nom.fill('E2ETest');
    await formulaire.locator('input[name="visitor_first_name"]').fill('Playwright');
    await formulaire.locator('input[name="visitor_email"]').fill('e2e@example.invalid');
    const addr = formulaire.locator('input[name="visitor_address"]');
    if (await addr.count()) await addr.fill('1 rue de Test');
    const obj = formulaire.locator('input[name="message_object"]');
    if (await obj.count()) await obj.fill('E2EContact');
    await formulaire.locator('textarea[name="message"], [name="message"]').first().fill('Message e2e — env de test, captcha mocké.');
    // sélectionner un destinataire si requis
    const dest = formulaire.locator('select[name="contact"], select').first();
    if (await dest.count()) await dest.selectOption({ index: 1 }).catch(() => {});
    // captcha : neutralisé par l'env de test (WireMock « valide » ou désactivé en profil e2e)
    await formulaire.locator('button[type="submit"], input[type="submit"]').first().click();
    await page.waitForLoadState('domcontentloaded').catch(() => {});
    const mail = await waitForMail((m) => /E2EContact|contact/i.test(`${m.subject} ${m.body}`), 12_000);
    expect(mail.to.join(','), 'destinataire du mail contact').toContain('@');
  });
});
