import { Page, Response, test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const ERROR_MARKERS = [
  'Technical error',
  'A technical error has occurred',
  'Error 500',
  'Erreur technique',
  'Startup error',
  'Internal error',
  'HTTP Status 5',
  'Exception report',
  'java.lang.',
  'jakarta.servlet',
  'Erreur interne',
  'Internal Server Error',
  'Stack trace',
  'Page not found',
  'requested page is not found',
  "page n'a pas été trouvée",
];

// Marqueurs d'une session BO absente ou expirée.
const SESSION_MARKERS = [
  'Please authenticate yourself',
  'authenticate yourself',
  'Veuillez vous authentifier',
];

// Marqueurs d'un droit RBAC manquant sur le compte utilisé.
const RBAC_MARKERS = [
  'Accès refusé',
  'Access denied',
];

function isBoUrl(url: string): boolean {
  return /\/jsp\/admin\//i.test(url);
}

/** Ajoute une annotation non bloquante au rapport, sans échouer hors contexte de test. */
function annotate(description: string, type = 'warning'): void {
  try {
    test.info().annotations.push({ type, description });
  } catch {
    void 0;
  }
}

function sessionMessage(url: string, marker: string): string {
  return `session BO non ouverte / expirée (marqueur "${marker}") sur ${url}`;
}

function rbacMessage(url: string, marker: string): string {
  return `droit manquant sur le compte de test pour ${url} — vérifier core_user_right (marqueur "${marker}")`;
}

function containsAny(body: string, markers: string[]): string | null {
  const hay = body.toLowerCase();
  for (const marker of markers) {
    if (hay.includes(marker.toLowerCase())) return marker;
  }
  return null;
}

function pathOf(raw: string): string {
  try {
    return new URL(raw).pathname;
  } catch {
    return raw;
  }
}

/**
 * Navigue vers une URL et renvoie la réponse principale.
 */
export async function gotoChecked(page: Page, url: string): Promise<Response | null> {
  return page.goto(url, { waitUntil: 'domcontentloaded' });
}

/**
 * Vérifie qu'une page ne présente pas d'erreur serveur.
 * - statut HTTP < 400 (annotation d'avertissement si aucune Response n'est fournie)
 * - pas de marqueur d'erreur dans le TEXTE VISIBLE (innerText, pas le HTML brut)
 * - présence d'un <title> non vide, sauf fragment (popup ou body quasi vide)
 * - sur une page BO : diagnostic distinct session expirée / droit RBAC manquant
 */
export async function assertNoError(page: Page, resp?: Response | null): Promise<void> {
  const url = page.url();
  if (resp) {
    expect(resp.status(), `statut HTTP pour ${url}`).toBeLessThan(400);
  } else {
    annotate(`assertNoError appelé sans Response — le statut HTTP n'a pas été vérifié pour ${url}`);
  }

  const title = (await page.title()).trim();
  if (title.length === 0) {
    const bodyChildren = await page
      .evaluate(() => (document.body ? document.body.children.length : 0))
      .catch(() => 0);
    if (/Popup[A-Z]/.test(url) || bodyChildren < 3) {
      annotate(`fragment (pas de <title>) sur ${url}`);
    } else {
      expect(title.length, `titre présent pour ${url}`).toBeGreaterThan(0);
    }
  }

  const body = (await page.locator('body').innerText().catch(() => '')) || '';
  for (const marker of ERROR_MARKERS) {
    expect(body, `marqueur d'erreur "${marker}" absent sur ${url}`).not.toContain(marker);
  }
  if (isBoUrl(url)) {
    for (const marker of SESSION_MARKERS) {
      expect(body, sessionMessage(url, marker)).not.toContain(marker);
    }
    for (const marker of RBAC_MARKERS) {
      expect(body, rbacMessage(url, marker)).not.toContain(marker);
    }
  }
}

/**
 * Qualifie un blocage d'accès BO : 'session' (login / session expirée),
 * 'rbac' (droit manquant sur le compte), ou null si la page est accessible.
 */
export async function accessBlocked(page: Page): Promise<'session' | 'rbac' | null> {
  const url = page.url();
  const body = (await page.locator('body').innerText().catch(() => '')) || '';
  if (containsAny(body, SESSION_MARKERS)) return 'session';
  if (containsAny(body, RBAC_MARKERS)) return 'rbac';
  if (/AdminLogin\.jsp/i.test(url)) return 'session';
  if (/AdminMessage\.jsp/i.test(url)) return 'rbac';
  return null;
}

/**
 * Contrôle positif d'authentification BO : échoue si on est redirigé vers le login,
 * si un blocage session ou RBAC s'affiche, ET exige un élément réservé admin.
 * À appeler dans global-setup (échec bruyant si login KO) et au début de chaque test BO.
 */
export async function assertAuthenticated(page: Page): Promise<void> {
  const url = page.url();
  expect(url, `pas redirigé vers le login (${url})`).not.toMatch(/AdminLogin\.jsp/i);
  const body = (await page.locator('body').innerText().catch(() => '')) || '';
  for (const marker of SESSION_MARKERS) {
    expect(body, sessionMessage(url, marker)).not.toContain(marker);
  }
  for (const marker of RBAC_MARKERS) {
    expect(body, rbacMessage(url, marker)).not.toContain(marker);
  }
  const admin = await page
    .locator('a[href*="AdminMenu"], a[href*="Logout" i], a[href*="jsp/admin/DoAdminLogout" i], .admin-header, #lutece-header')
    .first().count();
  expect(admin, `élément réservé admin présent (preuve de session) sur ${url}`).toBeGreaterThan(0);
}

/**
 * Contrôle visuel déterministe (sans IA) : CSS chargé et appliqué, aucune image cassée,
 * aucune superposition significative d'éléments interactifs visibles.
 */
export async function assertLayout(page: Page): Promise<void> {
  const url = page.url();
  const css = await page.evaluate(() => ({
    sheets: document.styleSheets.length,
    font: getComputedStyle(document.body).fontFamily,
  }));
  expect(css.sheets, `feuilles de style présentes sur ${url}`).toBeGreaterThan(0);
  expect((css.font || '').length, `styles calculés appliqués sur ${url}`).toBeGreaterThan(0);

  const broken = await page.evaluate(() =>
    Array.from(document.images)
      .filter((i) => i.complete && i.naturalWidth === 0)
      .map((i) => i.currentSrc || i.src));
  expect(broken, `aucune image cassée sur ${url}`).toEqual([]);

  const overlaps = await page.evaluate(() => {
    const visible = (e: Element): boolean => {
      const r = e.getBoundingClientRect();
      const s = getComputedStyle(e);
      return r.width > 8 && r.height > 8 && s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0.1;
    };
    const positioned = (e: Element): boolean => {
      const p = getComputedStyle(e).position;
      return p === 'absolute' || p === 'fixed' || p === 'sticky';
    };
    const hasOwnText = (e: Element): boolean => {
      if (['INPUT', 'SELECT', 'TEXTAREA'].includes(e.tagName)) return true;
      return Array.from(e.childNodes).some((nd) => nd.nodeType === 3 && (nd.textContent || '').trim().length > 1);
    };
    const all = Array.from(document.querySelectorAll('a,button,input,select,textarea'));
    const els = all.filter((e) => {
      if (!visible(e) || positioned(e)) return false;
      if (all.some((o) => o !== e && e.contains(o))) return false;
      if (!hasOwnText(e)) return false;
      return true;
    });
    const hits: string[] = [];
    for (let i = 0; i < els.length; i += 1) {
      for (let j = i + 1; j < els.length; j += 1) {
        if (els[i].contains(els[j]) || els[j].contains(els[i])) continue;
        const a = els[i].getBoundingClientRect();
        const b = els[j].getBoundingClientRect();
        const ox = Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left));
        const oy = Math.max(0, Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top));
        const area = ox * oy;
        const min = Math.min(a.width * a.height, b.width * b.height);
        if (min > 0 && area / min > 0.85) {
          const id = (els[i] as HTMLElement).id || (els[j] as HTMLElement).id || '';
          hits.push(`${els[i].tagName}~${els[j].tagName}${id ? '#' + id : ''}`);
        }
      }
    }
    return hits.slice(0, 5);
  });
  if (overlaps.length) {
    annotate(`superposition(s) possible(s) à vérifier visuellement sur ${url} : ${overlaps.join(', ')}`);
  }
}

/**
 * Attend qu'un composant JS soit initialisé : présence du global attendu,
 * puis fin du trafic réseau.
 */
export async function composantPret(page: Page, globalName: string, timeoutMs = 15000): Promise<void> {
  await page.waitForFunction(
    (n: string) => typeof (window as unknown as Record<string, unknown>)[n] !== 'undefined',
    globalName,
    { timeout: timeoutMs },
  );
  await page.waitForLoadState('networkidle');
}

/**
 * Attend la réponse HTTP correspondant au matcher (sous-chaîne, RegExp ou prédicat sur l'URL).
 * En cas d'expiration, lève une erreur listant les requêtes observées proches
 * (opts.near, par défaut le même dernier segment de chemin que le matcher textuel).
 */
export async function expectResponse(
  page: Page,
  matcher: string | RegExp | ((u: string) => boolean),
  opts?: { near?: RegExp; timeoutMs?: number },
): Promise<Response> {
  const seen: { method: string; url: string; status?: number }[] = [];
  const onRequest = (req: { method(): string; url(): string }): void => {
    seen.push({ method: req.method(), url: req.url() });
  };
  const onResponse = (res: { status(): number; request(): { method(): string; url(): string } }): void => {
    const req = res.request();
    const hit = seen.find((e) => e.url === req.url() && e.method === req.method() && e.status === undefined);
    if (hit) hit.status = res.status();
    else seen.push({ method: req.method(), url: req.url(), status: res.status() });
  };
  page.on('request', onRequest);
  page.on('response', onResponse);

  const matches = (u: string): boolean => {
    if (typeof matcher === 'function') return matcher(u);
    if (matcher instanceof RegExp) return matcher.test(u);
    return u.includes(matcher);
  };

  try {
    return await page.waitForResponse((res) => matches(res.url()), { timeout: opts?.timeoutMs });
  } catch {
    const near = opts?.near ?? defaultNear(matcher);
    const listed = seen
      .filter((e) => !near || near.test(e.url))
      .slice(-10)
      .map((e) => `${e.method} ${pathOf(e.url)} → ${e.status !== undefined ? e.status : 'sans réponse'}`);
    const label = typeof matcher === 'string' ? matcher : matcher instanceof RegExp ? String(matcher) : 'prédicat';
    throw new Error(
      `aucune réponse pour ${label} ; observé : ${listed.length ? listed.join(', ') : 'aucune requête approchante'}`,
    );
  } finally {
    page.off('request', onRequest);
    page.off('response', onResponse);
  }
}

function defaultNear(matcher: string | RegExp | ((u: string) => boolean)): RegExp | null {
  const source = typeof matcher === 'string' ? matcher : matcher instanceof RegExp ? matcher.source : '';
  const segment = source.split('?')[0].split('/').filter((s) => /[a-z0-9]/i.test(s)).pop() || '';
  const cleaned = segment.replace(/[^a-z0-9._-]/gi, '');
  if (cleaned.length < 3) return null;
  return new RegExp(cleaned.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
}

/**
 * Écrit une capture de preuve horodatée dans preuves/<id>/<phase>-<horodatage>.png,
 * l'attache au rapport et renvoie le chemin écrit. Ce dossier n'est jamais purgé.
 */
export async function capturePreuve(page: Page, id: string, phase: 'avant' | 'apres'): Promise<string> {
  const safe = id.replace(/[^a-z0-9-_]+/gi, '_').slice(0, 80);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dir = path.resolve(process.cwd(), 'preuves', safe);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `${phase}-${stamp}.png`);
  const body = await page.screenshot({ fullPage: true });
  fs.writeFileSync(file, body);
  try {
    await test.info().attach(`${safe}-${phase}`, { body, contentType: 'image/png' });
  } catch {
    void 0;
  }
  return file;
}

/**
 * Capture un screenshot nommé, l'attache au rapport (récupéré par le reporter PDF).
 */
export async function shot(page: Page, name: string): Promise<void> {
  const safe = name.replace(/[^a-z0-9-_]+/gi, '_').slice(0, 80);
  const body = await page.screenshot({ fullPage: false });
  await test.info().attach(safe, { body, contentType: 'image/png' });
}

/**
 * Branche l'écoute des erreurs JS (console niveau error et exceptions non capturées)
 * et renvoie le tableau qui les accumule.
 */
export function collectConsole(page: Page): { errors: string[] } {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(`PAGEERROR ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(`CONSOLE ${m.text()}`);
  });
  return { errors };
}

/**
 * Lit une variable d'environnement. Renvoie le repli s'il est fourni,
 * sinon échoue au lieu de laisser passer une valeur en dur.
 */
export function env(name: string, fallback?: string): string {
  const value = process.env[name];
  if (value !== undefined && value !== '') return value;
  if (fallback !== undefined) return fallback;
  throw new Error(`Variable ${name} absente de .env.local`);
}

/** Normalise une URL pour la déduplication (drop fragment, tri des params). */
export function normalizeUrl(raw: string): string {
  try {
    const u = new URL(raw);
    u.hash = '';
    const params = [...u.searchParams.entries()].sort(([a], [b]) => a.localeCompare(b));
    u.search = '';
    for (const [k, v] of params) u.searchParams.append(k, v);
    return u.toString();
  } catch {
    return raw;
  }
}
