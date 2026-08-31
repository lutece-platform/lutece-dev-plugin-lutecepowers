import { chromium, FullConfig, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { BASE_URL } from '../playwright.config';
import { discoverFoUrls, discoverBoFeatures, BoFeature } from './lib/crawler';
import { assertAuthenticated } from './lib/helpers';
import { query, closeDb } from './lib/db';

const ADMIN_USER = process.env.ADMIN_USER || 'admin';
const ADMIN_PASS = process.env.ADMIN_PASS || 'adminadmin';
const ADMIN_SOURCE = process.env.ADMIN_USER && process.env.ADMIN_PASS ? '.env.local' : 'défauts Lutèce (admin/adminadmin)';
const PLUGIN_NAME = process.env.PLUGIN_NAME || '';
const PLUGIN_XML = process.env.PLUGIN_XML || '';
const UPLOAD_HANDLER = process.env.UPLOAD_HANDLER || '';
const SITE_DIR = process.env.SITE_DIR || '';
const MANIFEST_TTL_H = Number(process.env.MANIFEST_TTL_H || 24);

const ARTIFACTS = path.resolve(process.cwd(), '.artifacts');
const STORAGE_STATE = 'storageState.json';
const MANIFEST_FO = path.join(ARTIFACTS, 'urls-fo.json');
const MANIFEST_BO = path.join(ARTIFACTS, 'urls-bo.json');
const MANIFEST_META = path.join(ARTIFACTS, 'manifests-meta.json');

interface ManifestesMeta {
  generatedAt: string;
  baseUrl: string;
  fo: number;
  bo: number;
}

interface Fraicheur {
  frais: boolean;
  motif: string;
}

/** Journalise une ligne préfixée par l'étape. */
function journal(message: string): void {
  // eslint-disable-next-line no-console
  console.log(`[global-setup] ${message}`);
}

async function globalSetup(_config: FullConfig): Promise<void> {
  fs.mkdirSync(ARTIFACTS, { recursive: true });

  controlerCheminSite();
  await fixerFamilleUploadSite();

  const fraicheur = evaluerManifestes();
  const sessionPresente = fs.existsSync(STORAGE_STATE);
  if (process.env.FORCE_SETUP !== '1' && sessionPresente && fraicheur.frais && await sessionEncoreValide()) {
    journal(`Session vivante + manifestes réutilisés — ${fraicheur.motif} (FORCE_SETUP=1 pour forcer).`);
    await controlerDroitsRbac();
    return;
  }
  if (!fraicheur.frais) journal(`Découverte relancée — ${fraicheur.motif}.`);

  const browser = await chromium.launch();
  const context = await browser.newContext({ ignoreHTTPSErrors: true, baseURL: BASE_URL });
  const page = await context.newPage();

  // 1) Découverte FO (public, sans authentification).
  const foUrls = await discoverFoUrls(page, BASE_URL, { maxPages: 50, maxDepth: 3 });
  fs.writeFileSync(MANIFEST_FO, JSON.stringify(foUrls, null, 2));

  // 2) Login BO — UNE SEULE FOIS.
  await page.goto(new URL('jsp/admin/AdminLogin.jsp', BASE_URL).toString(), { waitUntil: 'domcontentloaded' });
  // eslint-disable-next-line no-console
  console.log(`[global-setup] identifiants BO : ${ADMIN_USER} (source : ${ADMIN_SOURCE})`);
  await fillLogin(page);
  await page.waitForLoadState('networkidle').catch(() => {});

  // Contrôle positif : aller sur une vraie page BO et PROUVER l'authentification.
  await page.goto(new URL('jsp/admin/ManageProperties.jsp', BASE_URL).toString(), { waitUntil: 'domcontentloaded' });
  try {
    await assertAuthenticated(page);
  } catch (e) {
    throw new Error(`[global-setup] Login BO échoué (session non ouverte) — identifiants ? verrou anti-brute-force (core_connections_log) ? Cause : ${(e as Error).message}`);
  }
  await context.storageState({ path: STORAGE_STATE });

  // 3) Découverte BO (authentifié).
  const prefixes = (process.env.PLUGIN_NAME || '').split(',').map((s) => s.trim()).filter(Boolean);
  const boFeatures = prioriserPlugin(await discoverBoFeatures(page, BASE_URL, {
    maxPages: prefixes.length ? 60 : 40,
    pluginPrefixes: prefixes.length ? prefixes : undefined,
    maxCoreFeatures: 8,
  }));
  fs.writeFileSync(MANIFEST_BO, JSON.stringify(boFeatures, null, 2));

  ecrireMeta({
    generatedAt: new Date().toISOString(),
    baseUrl: BASE_URL,
    fo: foUrls.length,
    bo: boFeatures.length,
  });

  await browser.close();
  await controlerDroitsRbac();
}

/**
 * Ouvre une page BO avec la session enregistrée et vérifie qu'elle est authentifiée.
 * Renvoie false (et journalise) si la session a expiré.
 */
async function sessionEncoreValide(): Promise<boolean> {
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext({
      ignoreHTTPSErrors: true, baseURL: BASE_URL, storageState: STORAGE_STATE,
    });
    const page = await context.newPage();
    await page.goto(new URL('jsp/admin/ManageProperties.jsp', BASE_URL).toString(), { waitUntil: 'domcontentloaded' });
    await assertAuthenticated(page);
    return true;
  } catch {
    journal('Session enregistrée expirée -> reconnexion.');
    return false;
  } finally {
    await browser.close();
  }
}

/**
 * Demande la famille « site » du JS d'upload asynchrone avant toute spec, ce qui fixe l'endpoint de
 * dépôt sur jsp/site/upload pour la durée de vie du serveur. Sans effet si UPLOAD_HANDLER est absent.
 */
async function fixerFamilleUploadSite(): Promise<void> {
  if (!UPLOAD_HANDLER) return;
  const url = new URL(
    'jsp/site/plugins/asynchronousupload/GetMainUploadJs.jsp'
      + `?handler=${encodeURIComponent(UPLOAD_HANDLER)}&maxFileSize=10485760`,
    BASE_URL,
  ).toString();
  try {
    const reponse = await fetch(url);
    const corps = await reponse.text();
    const famille = /jsp\/admin\/upload/.test(corps) ? 'admin' : 'site';
    journal(`famille d'upload servie : ${famille} (handler ${UPLOAD_HANDLER}, HTTP ${reponse.status})`);
    if (famille === 'admin') {
      journal('cache déjà fixé sur la famille admin — redémarrer le serveur avant les specs de téléversement.');
    }
  } catch (e) {
    journal(`famille d'upload non déterminée : ${(e as Error).message}`);
  }
}

/** Avertit si le chemin du site déclaré (SITE_DIR) contient une espace. */
function controlerCheminSite(): void {
  if (!SITE_DIR) return;
  if (!/\s/.test(SITE_DIR)) return;
  journal('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
  journal(`!!! SITE_DIR contient une espace : « ${SITE_DIR} »`);
  journal('!!! AppPathService.getResourceStream ne chargera pas tous les descripteurs :');
  journal('!!! le BO peut rendre 500 alors que le FO répond 200. Déplacer le site dans');
  journal('!!! un chemin sans espace avant d\'interpréter le moindre résultat.');
  journal('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
}

/**
 * Journalise les droits déclarés par le descripteur PLUGIN_XML qui manquent au compte ADMIN_USER
 * dans core_user_right. Contrôle optionnel, jamais bloquant.
 */
async function controlerDroitsRbac(): Promise<void> {
  if (!PLUGIN_XML) return;
  try {
    if (!fs.existsSync(PLUGIN_XML)) {
      journal(`PLUGIN_XML introuvable : ${PLUGIN_XML} — contrôle des droits ignoré.`);
      return;
    }
    const droits = lireDroitsDescripteur(fs.readFileSync(PLUGIN_XML, 'utf-8'));
    if (droits.length === 0) {
      journal(`aucun droit déclaré dans ${path.basename(PLUGIN_XML)} — contrôle des droits sans objet.`);
      return;
    }
    const lignes = await query(
      'SELECT id_right FROM core_user_right r JOIN core_admin_user u ON u.id_user = r.id_user WHERE u.access_code = ?',
      [ADMIN_USER],
    );
    const accordes = new Set<string>(lignes.map((l) => String(l.id_right)));
    const manquants = droits.filter((d) => !accordes.has(d));
    if (manquants.length === 0) {
      journal(`droits vérifiés pour ${ADMIN_USER} : ${droits.length}/${droits.length} accordés.`);
      return;
    }
    journal('========================================================================');
    journal(`droits manquants pour ${ADMIN_USER} : ${manquants.join(', ')}`);
    journal('un droit manquant se présente comme un défaut fonctionnel (page refusée,');
    journal('action sans effet). Vérifier avant d\'ouvrir une anomalie.');
    journal('========================================================================');
  } catch (e) {
    journal(`contrôle des droits impossible : ${(e as Error).message}`);
  } finally {
    await closeDb().catch(() => {});
  }
}

/** Extrait les identifiants de droits d'un descripteur de plugin Lutèce. */
function lireDroitsDescripteur(xml: string): string[] {
  const trouves = new Set<string>();
  const motifs = [
    /<feature-id>\s*([^<\s]+)\s*<\/feature-id>/g,
    /<right-id>\s*([^<\s]+)\s*<\/right-id>/g,
    /<right\s[^>]*\bid\s*=\s*"([^"]+)"/g,
  ];
  for (const motif of motifs) {
    for (const m of xml.matchAll(motif)) {
      if (m[1]) trouves.add(m[1].trim());
    }
  }
  return [...trouves];
}

/** Remonte en tête du manifeste BO les fonctionnalités portées par le plugin cible (PLUGIN_NAME). */
function prioriserPlugin(features: BoFeature[]): BoFeature[] {
  if (!PLUGIN_NAME) return features;
  const cible = PLUGIN_NAME.toLowerCase();
  const porte = (f: BoFeature) => f.url.toLowerCase().includes(cible) || f.label.toLowerCase().includes(cible);
  const dedans = features.filter(porte);
  const dehors = features.filter((f) => !porte(f));
  journal(`plugin cible ${PLUGIN_NAME} : ${dedans.length} fonctionnalité(s) BO priorisée(s) sur ${features.length}.`);
  return [...dedans, ...dehors];
}

/** Renvoie les entrées d'un manifeste, en acceptant le format tableau nu comme le format enveloppé. */
function lireManifeste<T>(fichier: string): T[] | null {
  if (!fs.existsSync(fichier)) return null;
  try {
    const brut: unknown = JSON.parse(fs.readFileSync(fichier, 'utf-8'));
    if (Array.isArray(brut)) return brut as T[];
    if (brut && typeof brut === 'object') {
      const enveloppe = (brut as { urls?: unknown }).urls;
      if (Array.isArray(enveloppe)) return enveloppe as T[];
    }
    return null;
  } catch {
    return null;
  }
}

function lireMeta(): ManifestesMeta | null {
  if (!fs.existsSync(MANIFEST_META)) return null;
  try {
    const brut = JSON.parse(fs.readFileSync(MANIFEST_META, 'utf-8')) as Partial<ManifestesMeta>;
    if (!brut.generatedAt || !brut.baseUrl) return null;
    return { generatedAt: brut.generatedAt, baseUrl: brut.baseUrl, fo: brut.fo ?? 0, bo: brut.bo ?? 0 };
  } catch {
    return null;
  }
}

function ecrireMeta(meta: ManifestesMeta): void {
  fs.writeFileSync(MANIFEST_META, JSON.stringify(meta, null, 2));
}

/** Vérifie présence, BASE_URL d'origine et âge (MANIFEST_TTL_H) des manifestes de découverte. */
function evaluerManifestes(): Fraicheur {
  const fo = lireManifeste<string>(MANIFEST_FO);
  const bo = lireManifeste<BoFeature>(MANIFEST_BO);
  if (!fo || !bo) return { frais: false, motif: 'manifeste FO ou BO absent ou illisible' };
  const meta = lireMeta();
  if (!meta) return { frais: false, motif: 'horodatage des manifestes absent' };
  if (meta.baseUrl !== BASE_URL) {
    return { frais: false, motif: `manifestes produits pour ${meta.baseUrl}, BASE_URL courante ${BASE_URL}` };
  }
  const ageH = (Date.now() - Date.parse(meta.generatedAt)) / 3_600_000;
  if (!Number.isFinite(ageH) || ageH < 0) return { frais: false, motif: 'horodatage des manifestes illisible' };
  if (ageH > MANIFEST_TTL_H) {
    return { frais: false, motif: `manifestes âgés de ${ageH.toFixed(1)} h > MANIFEST_TTL_H=${MANIFEST_TTL_H} h` };
  }
  return {
    frais: true,
    motif: `âge ${ageH.toFixed(1)} h (TTL ${MANIFEST_TTL_H} h), ${fo.length} URL FO / ${bo.length} fonctionnalité(s) BO`,
  };
}

async function fillLogin(page: Page): Promise<void> {
  const user = page.locator('input[name="access_code"], input#access_code, input[name="j_username"]').first();
  const pass = page.locator('input[name="password"], input#password, input[name="j_password"]').first();
  await user.fill(ADMIN_USER);
  await pass.fill(ADMIN_PASS);
  const submit = page.locator('button[type="submit"], input[type="submit"], button:has-text("Connexion")').first();
  await submit.click();
}

export default globalSetup;
