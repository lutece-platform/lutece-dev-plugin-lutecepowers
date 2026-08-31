export interface ShotEntry {
  label: string;
  file: string;
}

export interface AnnotationEntry {
  type: string;
  description?: string;
}

export interface TestEntry {
  title: string;
  suite: string;
  status: string;
  durationMs: number;
  error?: string;
  shots: ShotEntry[];
  annotations?: AnnotationEntry[];
}

export interface Summary {
  status: string;
  totalMs: number;
  generatedAt: string;
}

export type Verdict = 'passed' | 'failed' | 'na' | 'env-absent' | 'skipped';

const LIB: Record<Verdict, { badge: string; cls: string }> = {
  passed: { badge: '✔ Réussi', cls: 'ok' },
  failed: { badge: '✘ Échec', cls: 'ko' },
  na: { badge: '⊘ Non applicable', cls: 'na' },
  'env-absent': { badge: '⚙ Environnement absent', cls: 'env' },
  skipped: { badge: '– Ignoré', cls: 'skip' },
};

function esc(s: string): string {
  return s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] as string));
}

function fmtMs(ms: number): string {
  if (ms < 1000) return `${Math.round(ms)} ms`;
  const s = ms / 1000;
  if (s < 60) return `${s.toFixed(1)} s`;
  const m = Math.floor(s / 60);
  return `${m} min ${Math.round(s - m * 60)} s`;
}

function annotationsOf(e: TestEntry, type: string): AnnotationEntry[] {
  return (e.annotations || []).filter((a) => a.type === type);
}

/** Classe un test en échec réel, non applicable, environnement absent, réussi ou ignoré. */
export function verdictOf(e: TestEntry): Verdict {
  if (annotationsOf(e, 'env-absent').length) return 'env-absent';
  if (annotationsOf(e, 'na').length) return 'na';
  if (e.status === 'failed' || e.status === 'timedOut') return 'failed';
  if (e.status === 'skipped') return 'skipped';
  if (e.status === 'passed') return 'passed';
  return 'failed';
}

function anchorOf(e: TestEntry, i: number): string {
  const base = e.title.replace(/[^a-z0-9]+/gi, '-').replace(/^-+|-+$/g, '').slice(0, 50).toLowerCase();
  return `t${i}-${base || 'test'}`;
}

function motif(e: TestEntry, verdict: Verdict): string {
  const list = verdict === 'na' ? annotationsOf(e, 'na') : annotationsOf(e, 'env-absent');
  return list.map((a) => a.description || '').filter(Boolean).join(' · ');
}

/** Libellé de la cible testée, dérivé de BASE_URL (context-root), sans valeur de projet en dur. */
function cibleTestee(): string {
  const raw = process.env.BASE_URL || '';
  try {
    const u = new URL(raw);
    const seg = u.pathname.split('/').filter(Boolean).pop();
    return seg ? `${seg} (${u.host})` : u.host;
  } catch {
    return 'cible non renseignée';
  }
}

/** Rend le rapport HTML : page de garde, compteurs par catégorie, sections par suite. */
export function renderHtml(entries: TestEntry[], summary: Summary): string {
  const cible = cibleTestee();
  const verdicts = entries.map(verdictOf);
  const nb = (v: Verdict): number => verdicts.filter((x) => x === v).length;

  const total = entries.length;
  const passed = nb('passed');
  const failed = nb('failed');
  const na = nb('na');
  const envAbsent = nb('env-absent');
  const skipped = nb('skipped');
  const applicable = passed + failed;
  const rate = applicable ? Math.round((passed / applicable) * 100) : 0;
  const warnings = entries.reduce((n, e) => n + annotationsOf(e, 'warning').length, 0);

  const suites = [...new Set(entries.map((e) => e.suite))];
  const foPages = entries.filter((e) => e.suite.startsWith('FO')).length;
  const boPages = entries.filter((e) => e.suite.startsWith('BO')).length;
  const totalShots = entries.reduce((n, e) => n + e.shots.length, 0);

  const anchors = entries.map((e, i) => anchorOf(e, i));

  const focus = entries
    .map((e, i) => ({ e, i }))
    .filter(({ i }) => verdicts[i] === 'failed')
    .map(({ e, i }) => `<li><a href="#${anchors[i]}">${esc(e.suite)} — ${esc(e.title)}</a></li>`)
    .join('');
  const focusBlock = failed
    ? `<div class="focus"><h3>Où regarder — ${failed} échec(s) réel(s)</h3><ol>${focus}</ol></div>`
    : `<div class="focus none"><h3>Aucun échec réel</h3><p>${na} non applicable(s) et ${envAbsent} environnement(s) absent(s) ne sont pas des défauts du produit.</p></div>`;

  const listeCat = (v: Verdict): string => entries
    .map((e, i) => ({ e, i }))
    .filter(({ i }) => verdicts[i] === v)
    .map(({ e, i }) => `<li><a href="#${anchors[i]}">${esc(e.title)}</a>${motif(e, v) ? ` — <span class="motif">${esc(motif(e, v))}</span>` : ''}</li>`)
    .join('');

  const naBlock = na
    ? `<div class="cat na"><h3>Non applicable (${na}) — hors périmètre de ce site/plugin</h3><ul>${listeCat('na')}</ul></div>`
    : '';
  const envBlock = envAbsent
    ? `<div class="cat env"><h3>Environnement absent (${envAbsent}) — à rejouer après mise en place</h3><ul>${listeCat('env-absent')}</ul></div>`
    : '';

  const suiteSections = suites.map((suite) => {
    const rows = entries
      .map((e, i) => ({ e, i }))
      .filter(({ e }) => e.suite === suite)
      .map(({ e, i }) => {
        const v = verdicts[i];
        const badge = `<span class="badge ${LIB[v].cls}">${LIB[v].badge}</span>`;
        const warns = annotationsOf(e, 'warning');
        const warnBadge = warns.length ? `<span class="badge warn">⚠ ${warns.length} avertissement(s)</span>` : '';
        const warnList = warns.length
          ? `<ul class="warnlist">${warns.map((a) => `<li>${esc(a.description || 'avertissement')}</li>`).join('')}</ul>`
          : '';
        const why = (v === 'na' || v === 'env-absent') && motif(e, v)
          ? `<p class="why">${esc(LIB[v].badge)} : ${esc(motif(e, v))}</p>`
          : '';
        const err = e.error && v === 'failed' ? `<pre class="err">${esc(e.error)}</pre>` : '';
        const trace = e.error && v !== 'failed' ? `<pre class="err muted">${esc(e.error)}</pre>` : '';
        const gallery = e.shots.length
          ? `<div class="gallery">${e.shots.map((s) => `
            <figure><img src="${esc(s.file)}" alt="${esc(s.label)}"/><figcaption>${esc(s.label)}</figcaption></figure>`).join('')}</div>`
          : '<p class="noshot">— aucun screenshot —</p>';
        return `
        <div class="test ${LIB[v].cls}" id="${anchors[i]}">
          <div class="test-head">
            <span class="test-title">${esc(e.title)}</span>
            <span class="test-meta">${badge} ${warnBadge} <span class="dur">${fmtMs(e.durationMs)}</span></span>
          </div>
          ${why}
          ${warnList}
          ${err}
          ${trace}
          ${gallery}
        </div>`;
      }).join('');
    return `<section class="suite"><h2>${esc(suite)}</h2>${rows}</section>`;
  }).join('');

  return `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"/>
<title>Rapport de tests e2e — ${esc(cible)}</title>
<style>
  :root { --navy:#12243b; --coral:#ff5a5f; --ok:#1f9d55; --ko:#e02424; --skip:#8a94a6; --na:#5b6675; --env:#b45309; --warn:#a16207; --ink:#1a2230; --muted:#5b6675; --line:#e3e8ef; }
  * { box-sizing: border-box; }
  body { font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; color: var(--ink); margin: 0; }
  .wrap { max-width: 1000px; margin: 0 auto; padding: 32px; }
  header.top { background: var(--navy); color: #fff; padding: 32px; border-radius: 0 0 8px 8px; }
  header.top h1 { margin: 0 0 4px; font-size: 26px; }
  header.top p { margin: 0; opacity: .8; font-size: 14px; }
  .confid { border: 2px solid var(--ko); background: #fff5f5; border-radius: 10px; padding: 16px 18px; margin: 24px 0; page-break-inside: avoid; }
  .confid h2 { margin: 0 0 8px; font-size: 16px; color: #7a1b1b; }
  .confid p, .confid li { font-size: 13px; margin: 6px 0; }
  .cards { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; margin: 24px 0 8px; }
  .card { border: 1px solid var(--line); border-radius: 10px; padding: 16px; text-align: center; }
  .card .n { font-size: 30px; font-weight: 700; }
  .card .l { font-size: 12px; color: var(--muted); text-transform: uppercase; letter-spacing: .5px; }
  .card.ok .n { color: var(--ok); } .card.ko .n { color: var(--ko); }
  .card.na .n { color: var(--na); } .card.env .n { color: var(--env); }
  .bar { height: 10px; background: var(--line); border-radius: 6px; overflow: hidden; margin: 8px 0 24px; }
  .bar > span { display: block; height: 100%; background: var(--ok); }
  .cov { font-size: 13px; color: var(--muted); margin-bottom: 24px; }
  .focus { border: 1px solid var(--ko); border-left: 5px solid var(--ko); border-radius: 8px; padding: 12px 16px; margin: 0 0 18px; page-break-inside: avoid; }
  .focus.none { border-color: var(--ok); border-left-color: var(--ok); }
  .focus h3 { margin: 0 0 6px; font-size: 15px; }
  .focus a, .cat a { color: inherit; }
  .cat { border: 1px solid var(--line); border-radius: 8px; padding: 12px 16px; margin: 0 0 18px; font-size: 13px; page-break-inside: avoid; }
  .cat.na { border-left: 5px solid var(--na); } .cat.env { border-left: 5px solid var(--env); }
  .cat h3 { margin: 0 0 6px; font-size: 15px; }
  .motif { color: var(--muted); }
  .suite { margin: 28px 0; }
  .suite h2 { font-size: 18px; border-left: 4px solid var(--coral); padding-left: 10px; }
  .test { border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px; margin: 12px 0; page-break-inside: avoid; }
  .test.ko { border-left: 5px solid var(--ko); }
  .test.na { border-left: 5px solid var(--na); }
  .test.env { border-left: 5px solid var(--env); }
  .test-head { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
  .test-title { font-weight: 600; }
  .badge { font-size: 12px; padding: 2px 8px; border-radius: 20px; color: #fff; white-space: nowrap; }
  .badge.ok { background: var(--ok); } .badge.ko { background: var(--ko); } .badge.skip { background: var(--skip); }
  .badge.na { background: var(--na); } .badge.env { background: var(--env); } .badge.warn { background: var(--warn); }
  .dur { color: var(--muted); font-size: 12px; margin-left: 8px; }
  .why { font-size: 13px; color: var(--muted); margin: 8px 0 0; }
  .warnlist { font-size: 12px; color: var(--warn); margin: 8px 0 0; padding-left: 18px; }
  .err { background: #fff5f5; color: #7a1b1b; padding: 8px 10px; border-radius: 6px; font-size: 12px; white-space: pre-wrap; }
  .err.muted { background: #f6f7f9; color: var(--muted); }
  .gallery { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; margin-top: 12px; }
  figure { margin: 0; border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
  figure img { width: 100%; display: block; }
  figcaption { font-size: 11px; color: var(--muted); padding: 6px 8px; background: #fafbfc; }
  .noshot { color: var(--muted); font-size: 12px; }
  footer { color: var(--muted); font-size: 12px; text-align: center; padding: 24px; }
</style></head>
<body>
  <header class="top">
    <h1>Rapport de tests e2e — ${esc(cible)}</h1>
    <p>Playwright · généré le ${esc(summary.generatedAt)} · durée totale ${fmtMs(summary.totalMs)}</p>
  </header>
  <div class="wrap">
    <div class="confid">
      <h2>Diffusion restreinte — données personnelles</h2>
      <p>Ce rapport agrège <b>${totalShots} capture(s)</b> d'un environnement alimenté par des données réelles :
      noms de sociétés, noms et prénoms, adresses postales, numéros de téléphone, adresses de courriel.</p>
      <ul>
        <li><b>Ne pas versionner</b> ce rapport (<code>rapport.html</code>, <code>rapport.pdf</code>), le dossier
        <code>report/screenshots/</code> ni le dossier <code>preuves/</code>.</li>
        <li><b>Ne pas transmettre</b> le PDF hors du cercle habilité à voir ces données ; un PDF de revue complète
        pèse plusieurs Mo et contient toutes les captures.</li>
        <li>Le projet de tests reste <b>hors du dépôt applicatif</b> ; les preuves durables vivent dans
        <code>preuves/</code>, archive <b>locale et non versionnée</b>, jamais purgée.</li>
      </ul>
    </div>
    <div class="cards">
      <div class="card"><div class="n">${total}</div><div class="l">Tests</div></div>
      <div class="card ok"><div class="n">${passed}</div><div class="l">Réussis</div></div>
      <div class="card ko"><div class="n">${failed}</div><div class="l">Échecs réels</div></div>
      <div class="card na"><div class="n">${na}</div><div class="l">Non applicable</div></div>
      <div class="card env"><div class="n">${envAbsent}</div><div class="l">Env. absent</div></div>
      <div class="card"><div class="n">${rate}%</div><div class="l">Taux sur applicables</div></div>
    </div>
    <div class="bar"><span style="width:${rate}%"></span></div>
    <p class="cov">Taux calculé sur les <b>${applicable}</b> test(s) applicable(s) (${passed} réussis / ${failed} échecs) —
    ${na} non applicable(s) et ${envAbsent} environnement(s) absent(s) sont <b>exclus</b> du décompte d'échecs.
    ${skipped} ignoré(s) · ${warnings} avertissement(s) <code>assertLayout</code>.</p>
    <p class="cov">Couverture : <b>${foPages}</b> vue(s) Front Office · <b>${boPages}</b> vue(s) Back Office · <b>${totalShots}</b> screenshots.</p>
    ${focusBlock}
    ${naBlock}
    ${envBlock}
    ${suiteSections}
  </div>
  <footer>Généré automatiquement par le reporter PDF Playwright — tests e2e Lutece. Diffusion restreinte.</footer>
</body></html>`;
}
