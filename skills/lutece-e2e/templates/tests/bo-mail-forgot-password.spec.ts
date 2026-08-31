import { test, expect } from '@playwright/test';
import { clearMails, waitForMail, mailhogUp } from './lib/mail';
import { env } from './lib/helpers';

// Flux d'envoi de mail SANS CAPTCHA : « mot de passe oublié » admin → Lutèce envoie un mail de
// réinitialisation, capturé par MailHog (le SMTP est redirigé vers MailHog dans l'env de test).
test.use({ storageState: { cookies: [], origins: [] } }); // flux public (non connecté)

test.describe('Back Office — envoi de mail (mot de passe oublié) vérifié via MailHog', () => {
  test('demande de réinitialisation → mail capturé', async ({ page }) => {
    const mailDispo = await mailhogUp();
    if (!mailDispo) {
      test.info().annotations.push({
        type: 'env-absent',
        description: 'MailHog injoignable — env de test non démarré (scripts/testenv/testenv.sh up mail)',
      });
    }
    test.skip(!mailDispo, 'MailHog absent — env de test non démarré (scripts/testenv/testenv.sh up mail)');

    await clearMails();
    await page.goto('jsp/admin/AdminForgotPassword.jsp', { waitUntil: 'domcontentloaded' });
    await page.locator('input[name="access_code"]').fill(env('ADMIN_USER', 'admin'));
    await page.locator('button[type="submit"], input[type="submit"]').first().click();
    await page.waitForLoadState('domcontentloaded').catch(() => {});

    // Effet réel vérifié : un mail a bien été émis (capturé par MailHog).
    const mail = await waitForMail(
      (m) => /mot de passe|password|initialis|r[ée]initialis/i.test(`${m.subject} ${m.body}`),
      12_000,
    );
    expect(mail.to.join(','), 'destinataire du mail').toContain('@');
  });
});
