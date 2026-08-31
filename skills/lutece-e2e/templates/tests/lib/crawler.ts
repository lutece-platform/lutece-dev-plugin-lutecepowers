import { Page } from '@playwright/test';
import { normalizeUrl } from './helpers';

export interface CrawlOptions {
  maxPages?: number;
  maxDepth?: number;
  /** Préfixes du plugin ciblé (nom de plugin, right, admin-feature) : ses écrans passent en tête du manifeste BO. */
  pluginPrefixes?: string[];
  /** Nombre maximum de fonctionnalités du socle conservées comme témoins (défaut 8), appliqué seulement si `pluginPrefixes` est fourni. */
  maxCoreFeatures?: number;
}

/** Statut d'une entrée de manifeste qui n'a pas pu être atteinte pendant la découverte. */
export type CrawlStatus = 'injoignable';

export interface BoFeature {
  label: string;
  url: string;
  status?: CrawlStatus;
}

/** Fragment ajouté à une URL FO inscrite au manifeste mais injoignable pendant la découverte. */
export const UNREACHABLE_MARKER = '#e2e-injoignable';

// Libellés/URLs à NE PAS actionner automatiquement (effet de bord / irréversible).
const DESTRUCTIVE = /(suppr|remove|delete|effac|envoyer|send|publi|valider|confirmer|d[ée]connex|logout|purge|vider|import|export)/i;

const EMBEDDED_SCHEME = /https?:\/\//i;

/**
 * Actionne les contrôles NON destructifs et sans navigation sortante d'une page
 * (boutons sans submit, onglets, contrôles de liste), en excluant tout ce qui a un
 * effet de bord. Renvoie ce qui a été cliqué vs ignoré (traçabilité).
 */
export async function exerciseControls(page: Page, budgetMs = 12_000): Promise<{ clicked: string[]; skipped: string[] }> {
  const abandon = { demande: false };
  let minuteur: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      exerciseControlsInner(page, budgetMs, abandon),
      new Promise<{ clicked: string[]; skipped: string[] }>((resolve) => {
        minuteur = setTimeout(() => {
          abandon.demande = true;
          resolve({ clicked: [], skipped: ['<budget dépassé>'] });
        }, budgetMs + 1500);
      }),
    ]);
  } finally {
    clearTimeout(minuteur);
  }
}

async function exerciseControlsInner(
  page: Page,
  budgetMs: number,
  abandon: { demande: boolean },
): Promise<{ clicked: string[]; skipped: string[] }> {
  const clicked: string[] = [];
  const skipped: string[] = [];
  const startUrl = page.url();
  const deadline = Date.now() + budgetMs;
  // Auto-dismiss des dialogues natifs (confirm/alert) qui bloqueraient l'exécution.
  const onDialog = (d: import('@playwright/test').Dialog) => { d.dismiss().catch(() => {}); };
  page.on('dialog', onDialog);
  const controls = page.locator('button:visible, [role="tab"]:visible, a[href]:visible');
  const n = Math.min(await controls.count(), 20);
  for (let i = 0; i < n; i += 1) {
    // Arrêt si : abandon demandé, navigation, page fermée, ou budget de temps épuisé.
    if (abandon.demande || page.isClosed() || page.url() !== startUrl || Date.now() > deadline) break;
    const el = controls.nth(i);
    const label = ((await el.innerText().catch(() => '')) || (await el.getAttribute('title').catch(() => '')) || '').trim();
    const href = (await el.getAttribute('href').catch(() => '')) || '';
    const type = (await el.getAttribute('type').catch(() => '')) || '';
    const role = (await el.getAttribute('role').catch(() => '')) || '';
    if (DESTRUCTIVE.test(label) || DESTRUCTIVE.test(href) || /submit/i.test(type)) {
      skipped.push(label || href);
      continue;
    }
    // Sûr = onglet, ou bouton sans submit, ou lien interne d'ancre (#). Pas de navigation sortante.
    const isSafe = role === 'tab' || (!href && type !== 'submit') || href.startsWith('#');
    if (!isSafe) {
      skipped.push(label || href);
      continue;
    }
    await el
      .click({ timeout: 1200, noWaitAfter: true })
      .then(() => clicked.push(label || href || '(sans libellé)'))
      .catch(() => skipped.push(label || href));
  }
  page.off('dialog', onDialog);
  return { clicked, skipped };
}

/** Indique si une entrée de manifeste (URL FO ou fonctionnalité BO) porte le statut « injoignable ». */
export function isUnreachable(entry: string | BoFeature): boolean {
  return typeof entry === 'string' ? entry.endsWith(UNREACHABLE_MARKER) : entry.status === 'injoignable';
}

/** Construit une URL, ou null si la chaîne n'est pas analysable. */
function toUrl(raw: string, base?: string): URL | null {
  try {
    return base === undefined ? new URL(raw) : new URL(raw, base);
  } catch {
    return null;
  }
}

/** Indique si le chemin ou la query d'une URL contient un second schéma http(s). */
function hasEmbeddedScheme(u: URL): boolean {
  return EMBEDDED_SCHEME.test(u.pathname + u.search);
}

/**
 * Résout un href en URL absolue. Tente de réparer un href contenant un second schéma
 * http(s) dans son chemin ou sa query, et renvoie null si le résultat reste malformé.
 */
export function resolveHref(href: string, base: string): URL | null {
  const direct = toUrl(href, base);
  if (direct && !hasEmbeddedScheme(direct)) return direct;

  const cut = href.lastIndexOf('http');
  const repaired = cut > 0 ? toUrl(href.slice(cut), base) : null;
  if (repaired && !hasEmbeddedScheme(repaired)) {
    // eslint-disable-next-line no-console
    console.log(`[crawler] href malformé réparé : ${href} → ${repaired.href}`);
    return repaired;
  }

  // eslint-disable-next-line no-console
  console.log(`[crawler] href malformé ignoré : ${href}`);
  return null;
}

/** Renvoie l'URL suffixée du marqueur « injoignable » (fragment, non envoyé au serveur). */
function markUnreachable(url: string): string {
  const u = toUrl(url);
  if (!u) return url + UNREACHABLE_MARKER;
  u.hash = UNREACHABLE_MARKER;
  return u.toString();
}

/** Première ligne d'un message d'erreur, pour un journal lisible. */
function firstLine(e: unknown): string {
  return String(e instanceof Error ? e.message : e).split('\n')[0].trim();
}

/**
 * Découverte automatique des pages FO par BFS depuis l'accueil.
 * Ne suit que les liens internes (même origine + sous le context-root), rejette les
 * href malformés et déduplique par URL normalisée ; borne profondeur et nombre de pages.
 * Les URL injoignables sont conservées au manifeste avec le marqueur `UNREACHABLE_MARKER`.
 * Journalise ce qui est couvert, écarté et plafonné (pas de troncature silencieuse).
 */
export async function discoverFoUrls(page: Page, baseUrl: string, opts: CrawlOptions = {}): Promise<string[]> {
  const maxPages = opts.maxPages ?? 25;
  const maxDepth = opts.maxDepth ?? 2;

  const origin = new URL(baseUrl).origin;
  const rootPath = new URL(baseUrl).pathname;

  const visited = new Set<string>();
  const queued = new Set<string>([normalizeUrl(baseUrl)]);
  const found: string[] = [];
  const unreachable: string[] = [];
  const queue: { url: string; depth: number }[] = [{ url: baseUrl, depth: 0 }];

  while (queue.length && found.length < maxPages) {
    const { url, depth } = queue.shift()!;
    const norm = normalizeUrl(url);
    if (visited.has(norm)) continue;
    visited.add(norm);

    try {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 20_000 });
    } catch (e) {
      found.push(markUnreachable(url));
      unreachable.push(url);
      // eslint-disable-next-line no-console
      console.log(`[crawler FO] URL injoignable inscrite au manifeste (statut injoignable) : ${url} — ${firstLine(e)}`);
      continue;
    }
    found.push(url);

    if (depth >= maxDepth) continue;

    const hrefs: string[] = await page.$$eval('a[href]', (as) =>
      as.map((a) => (a as HTMLAnchorElement).href).filter(Boolean),
    );

    for (const href of hrefs) {
      const abs = resolveHref(href, url);
      if (!abs) continue;
      abs.hash = '';
      if (abs.origin !== origin) continue;
      if (!abs.pathname.startsWith(rootPath)) continue;
      // Éviter le BO, les déconnexions, les téléchargements et les non-pages.
      if (/jsp\/admin\//i.test(abs.pathname)) continue;
      if (/logout|deconnexion|Logout/i.test(abs.href)) continue;
      if (/\.(pdf|zip|png|jpe?g|gif|css|js|ico|svg)(\?|$)/i.test(abs.pathname)) continue;
      const n = normalizeUrl(abs.href);
      if (visited.has(n) || queued.has(n)) continue;
      queued.add(n);
      queue.push({ url: abs.href, depth: depth + 1 });
    }
  }

  const remaining = queue.length;
  // eslint-disable-next-line no-console
  console.log(`[crawler FO] ${found.length} pages découvertes (plafond ${maxPages}, profondeur ${maxDepth}).` +
    (unreachable.length ? ` ${unreachable.length} injoignable(s) inscrite(s) au manifeste : ${unreachable.join(', ')}.` : '') +
    (remaining ? ` ${remaining} URL(s) en file non explorées (plafond atteint).` : ' File épuisée (couverture complète du périmètre borné).'));

  return found;
}

/** Indique si une fonctionnalité BO relève de l'un des préfixes de plugin fournis. */
function matchesPluginPrefix(feature: BoFeature, prefixes: string[]): boolean {
  const url = feature.url.toLowerCase();
  const label = feature.label.toLowerCase();
  return prefixes.some((p) => url.includes(`plugins/${p}`) || url.includes(p) || label.includes(p));
}

/**
 * Découverte des fonctionnalités du Back Office depuis le menu admin.
 * Requiert une session authentifiée (storageState).
 * Rejette les href malformés, exclut les handlers d'action `Do<Verbe>.jsp` et déduplique
 * par URL normalisée (hors jeton). Si `pluginPrefixes` est fourni, les fonctionnalités du
 * plugin sont placées en tête et celles du socle sont bornées à `maxCoreFeatures` témoins.
 */
export async function discoverBoFeatures(page: Page, baseUrl: string, opts: CrawlOptions = {}): Promise<BoFeature[]> {
  const maxPages = opts.maxPages ?? 40;
  const maxCoreFeatures = opts.maxCoreFeatures ?? 8;
  const prefixes = (opts.pluginPrefixes ?? []).map((p) => p.trim().toLowerCase()).filter(Boolean);
  const home = new URL('jsp/admin/AdminMenu.jsp', baseUrl).toString();
  try {
    await page.goto(home, { waitUntil: 'domcontentloaded' });
  } catch (e) {
    // eslint-disable-next-line no-console
    console.log(`[crawler BO] menu admin injoignable, inscrit au manifeste (statut injoignable) : ${home} — ${firstLine(e)}`);
    return [{ label: 'AdminMenu.jsp', url: home, status: 'injoignable' }];
  }

  const origin = new URL(baseUrl).origin;
  const raw: { label: string; url: string }[] = await page.$$eval('a[href]', (as) =>
    as
      .map((a) => ({ label: (a.textContent || '').trim(), url: (a as HTMLAnchorElement).href }))
      .filter((x) => x.url),
  );

  const seen = new Set<string>();
  const candidates: BoFeature[] = [];
  for (const { label, url } of raw) {
    const abs = resolveHref(url, home);
    if (!abs) continue;
    abs.hash = '';
    if (abs.origin !== origin) continue;
    if (!/jsp\/admin\//i.test(abs.pathname)) continue;
    // Ne garder que les points d'entrée de fonctionnalités, pas les actions destructrices.
    if (!/(Manage|View|Get|Home|jsp\/admin\/[A-Za-z]+\.jsp)/.test(abs.href)) continue;
    // Exclure les HANDLERS d'action (convention Lutèce Do<Verbe> : POST qui redirige, non affichable).
    if (/\/Do[A-Z][A-Za-z]*\.jsp/.test(abs.pathname)) continue;
    if (/logout|Logout|ChangeLanguage|doDelete|remove|Remove|Delete/i.test(abs.href)) continue;
    const key = dedupKey(abs);
    if (seen.has(key)) continue;
    seen.add(key);
    candidates.push({ label: label || abs.pathname.split('/').pop() || abs.href, url: abs.href });
  }

  if (!prefixes.length) {
    const kept = candidates.slice(0, maxPages);
    // eslint-disable-next-line no-console
    console.log(`[crawler BO] ${kept.length} fonctionnalité(s) admin découverte(s).` +
      (candidates.length > kept.length ? ` ${candidates.length - kept.length} écartée(s) (plafond ${maxPages}).` : ''));
    return kept;
  }

  const pluginFeatures = candidates.filter((f) => matchesPluginPrefix(f, prefixes));
  const coreFeatures = candidates.filter((f) => !matchesPluginPrefix(f, prefixes));
  const keptPlugin = pluginFeatures.slice(0, maxPages);
  const keptCore = coreFeatures.slice(0, Math.max(0, Math.min(maxCoreFeatures, maxPages - keptPlugin.length)));

  // eslint-disable-next-line no-console
  console.log(`[crawler] ${keptPlugin.length} features plugin, ${keptCore.length} features socle (témoins)` +
    ` — préfixes : ${prefixes.join(', ')}` +
    (pluginFeatures.length > keptPlugin.length ? ` ; ${pluginFeatures.length - keptPlugin.length} feature(s) plugin écartée(s) (plafond ${maxPages})` : '') +
    (coreFeatures.length > keptCore.length ? ` ; ${coreFeatures.length - keptCore.length} feature(s) socle écartée(s) (plafond ${maxCoreFeatures})` : '') + '.');
  if (!keptPlugin.length) {
    // eslint-disable-next-line no-console
    console.log(`[crawler BO] aucune fonctionnalité ne correspond aux préfixes ${prefixes.join(', ')} : préfixes à vérifier (PLUGIN_NAME, <right>, <admin-feature>) ou droits admin insuffisants.`);
  }

  return [...keptPlugin, ...keptCore];
}

/** Clé de déduplication d'une URL BO : URL normalisée, paramètres de jeton retirés. */
function dedupKey(abs: URL): string {
  const u = toUrl(normalizeUrl(abs.href));
  if (!u) return abs.href;
  u.search = u.search.replace(/^\?/, '').split('&').filter((p) => p && !/^token/i.test(p)).join('&');
  return u.toString();
}
