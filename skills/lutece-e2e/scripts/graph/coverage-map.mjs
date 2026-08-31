// Carte de couverture : croise .artifacts/graph.json avec les tests et manifestes existants,
// écrit report/graph-coverage.md (plan par vagues de 12) et .artifacts/to-generate.json
// (work-list triée par valeur décroissante).
import fs from 'node:fs';

if (!fs.existsSync('.artifacts/graph.json')) { console.error('graph.json absent — lancer build-graph.mjs d’abord'); process.exit(1); }
const g = JSON.parse(fs.readFileSync('.artifacts/graph.json', 'utf8'));

const TAILLE_VAGUE = 12;
const PLUGIN = (process.env.PLUGIN_NAME || '').trim().toLowerCase();

/** Lit un manifeste `.artifacts/urls-*.json` : tableau nu ou objet `{urls}`. */
const readManifest = (p) => {
  if (!fs.existsSync(p)) return [];
  const raw = JSON.parse(fs.readFileSync(p, 'utf8'));
  if (Array.isArray(raw)) return raw;
  if (raw && Array.isArray(raw.urls)) return raw.urls;
  return [];
};

const specFiles = fs.existsSync('tests')
  ? fs.readdirSync('tests').filter((f) => f.endsWith('.spec.ts')).map((f) => fs.readFileSync(`tests/${f}`, 'utf8'))
  : [];
/** URL portée par une entrée de manifeste (chaîne nue ou objet `{url}`). */
const asUrl = (x) => (typeof x === 'string' ? x : (x && typeof x.url === 'string' ? x.url : ''));
const hay = [
  ...readManifest('.artifacts/urls-fo.json').map(asUrl),
  ...readManifest('.artifacts/urls-bo.json').map(asUrl),
  ...specFiles,
].join('\n').toLowerCase();

const term = (n) => n.id.split(':').pop().split('#').pop().replace(/\.(html|jsp)$/i, '').toLowerCase();
const rows = g.nodes.map((n) => ({ ...n, covered: term(n).length > 2 && hay.includes(term(n)) }));

const by = {};
for (const r of rows) { by[r.type] ??= { c: 0, t: 0 }; by[r.type].t += 1; if (r.covered) by[r.type].c += 1; }
const uncovered = rows.filter((r) => !r.covered);

// ---------------------------------------------------------------- priorisation

const gabarits = [...new Set(rows.map((r) => r.source).filter((s) => typeof s === 'string' && /\.html$/i.test(s)))];
const ihm = gabarits
  .filter((f) => fs.existsSync(f))
  .map((f) => fs.readFileSync(f, 'utf8'))
  .join('\n')
  .toLowerCase();

const jetonsPlugin = PLUGIN
  ? [...new Set([PLUGIN, PLUGIN.replace(/^(plugin|module)-/, ''), PLUGIN.replace(/[-_]/g, '')].filter((s) => s.length > 2))]
  : [];

/** Vrai si le nœud appartient au plugin cible (PLUGIN_NAME), faux s'il vient du socle. */
const estCible = (r) => {
  if (!jetonsPlugin.length) return false;
  const cadre = `${r.source || ''} ${r.id || ''} ${r.label || ''}`.toLowerCase();
  return jetonsPlugin.some((j) => cadre.includes(j));
};

/** Vrai si le nœud est atteignable depuis l'IHM (déclaré au plugin.xml, gabarit, ou cité par un gabarit). */
const estAtteignable = (r) => {
  if (typeof r.source === 'string' && r.source.startsWith('plugin.xml')) return true;
  if (r.type === 'form' || r.type === 'list-control') return true;
  const t = term(r);
  return t.length > 2 && ihm.includes(t);
};

const POIDS_TYPE = { entity: 40, action: 30, form: 30, view: 10, 'list-control': 5 };

/** Valeur d'un nœud : plugin cible > type (action/form avant view) > atteignable par l'IHM. */
const valeur = (r) => (estCible(r) ? 100 : 0) + (POIDS_TYPE[r.type] ?? 0) + (estAtteignable(r) ? 5 : 0);

const lastTok = (s) => (s.trim().split(/\s+/).pop() || s);
const slug = (s) => s.replace(/[^a-z0-9]+/gi, '').slice(0, 28) || 'node';
const nodeName = (r) => slug(`${r.type}${lastTok(r.label)}`);

const candidats = uncovered
  .filter((r) => r.type === 'view' || r.type === 'action' || r.type === 'form' || r.type === 'entity')
  .map((r) => ({ r, cible: estCible(r), atteignable: estAtteignable(r), score: valeur(r) }))
  .sort((a, b) => b.score - a.score || a.r.type.localeCompare(b.r.type) || String(a.r.label).localeCompare(String(b.r.label)));

const seenNames = new Set();
for (const c of candidats) {
  let name = nodeName(c.r); let i = 1;
  while (seenNames.has(name)) { name = `${nodeName(c.r)}${i++}`; }
  seenNames.add(name);
  c.name = name;
}

const toGenerate = candidats.map((c) => ({
  name: c.name,
  kind: c.r.type === 'entity' ? 'entity' : 'node',
  type: c.r.type,
  label: c.r.label,
  source: c.r.source,
}));

fs.mkdirSync('.artifacts', { recursive: true });
fs.writeFileSync('.artifacts/to-generate.json', JSON.stringify(toGenerate, null, 2));

// ---------------------------------------------------------------- plan par vagues

const vagues = [];
for (let i = 0; i < candidats.length; i += TAILLE_VAGUE) vagues.push(candidats.slice(i, i + TAILLE_VAGUE));

/** Rendement attendu d'une vague, d'après sa composition (part de plugin cible, d'actions/formulaires, d'atteignables). */
const rendement = (lot) => {
  const part = (n) => n / lot.length;
  const cible = part(lot.filter((c) => c.cible).length);
  const af = part(lot.filter((c) => c.r.type === 'action' || c.r.type === 'form' || c.r.type === 'entity').length);
  const att = part(lot.filter((c) => c.atteignable).length);
  if (cible >= 0.5 && af >= 0.5) return 'fort — actions/formulaires du plugin cible : chaque item exerce un effet métier';
  if (cible >= 0.5) return 'bon — plugin cible, surtout des vues : défauts d’affichage plutôt que d’effet';
  if (af >= 0.5) return 'moyen — socle, actions/formulaires';
  if (att < 0.3) return 'faible — code peu atteignable par l’IHM : à traiter en dernier, voire à écarter';
  return 'moyen — socle, vues';
};

let md = '# Carte de couverture du graphe\n\n';
md += 'Chaque nœud du graphe doit avoir ≥ 1 test. « NON couvert » = fonctionnalité détectée mais pas testée.\n\n';
md += '> ⚠️ Matching par sous-chaîne (approximatif) : à recouper avec JaCoCo (Phase 3) pour l’exercice réel.\n\n';
for (const [t, v] of Object.entries(by)) md += `- **${t}** : ${v.c}/${v.t} couverts\n`;

md += `\n## Plan de génération — ${candidats.length} nœud(s) à couvrir, ${vagues.length} vague(s) de ${TAILLE_VAGUE}\n\n`;
md += `Le workflow \`generate-tests.js\` traite **${TAILLE_VAGUE} items par run**. Les vagues sont triées par valeur\n`;
md += 'décroissante : ne pas les prendre dans un autre ordre, et **s’arrêter quand le rendement devient faible**\n';
md += 'est un choix légitime — une couverture de 40 % concentrée sur les actions du plugin vaut mieux qu’une\n';
md += 'couverture de 100 % étalée sur le socle.\n\n';
md += `Critères, du plus fort au plus faible : **plugin cible** (\`PLUGIN_NAME\`${PLUGIN ? ` = \`${PLUGIN}\`` : ' — non fourni, critère inactif'}) ; `;
md += '**type** (`entity` > `action`/`form` > `view`) ; **atteignable par l’IHM** (déclaré au `plugin.xml`, gabarit, ou cité par un gabarit) plutôt que code défensif.\n\n';

if (!vagues.length) {
  md += 'Rien à générer : tous les nœuds atteignables sont déjà couverts.\n';
} else {
  md += '| Vague | Items | Plugin cible | action/form | view | Atteignables | Rendement attendu |\n|---|---|---|---|---|---|---|\n';
  vagues.forEach((lot, i) => {
    const cible = lot.filter((c) => c.cible).length;
    const af = lot.filter((c) => c.r.type === 'action' || c.r.type === 'form' || c.r.type === 'entity').length;
    const vues = lot.filter((c) => c.r.type === 'view').length;
    const att = lot.filter((c) => c.atteignable).length;
    md += `| ${i + 1} | ${lot.length} | ${cible} | ${af} | ${vues} | ${att} | ${rendement(lot)} |\n`;
  });
  md += '\n';
  vagues.forEach((lot, i) => {
    md += `### Vague ${i + 1} — ${lot.length} item(s)\n\n`;
    md += lot.map((c) => {
      const tags = [c.cible ? 'plugin cible' : 'socle', c.atteignable ? 'atteignable IHM' : 'non atteignable IHM'].join(', ');
      return `- \`${c.name}\` [${c.r.type}] ${c.r.label} — ${tags}  \n  ↳ ${c.r.source}`;
    }).join('\n') + '\n\n';
  });
  md += `Lancer une vague : \`Workflow({ scriptPath: "$SKILL/workflows/generate-tests.js", args: <${TAILLE_VAGUE} premiers items de .artifacts/to-generate.json> })\`,\n`;
  md += 'puis relancer `coverage-map.mjs` — les nœuds couverts par la vague disparaissent et le plan se recalcule.\n\n';
}

md += `## Annexe — tous les nœuds NON couverts (${uncovered.length})\n\n`;
const parType = {};
for (const r of uncovered) (parType[r.type] ??= []).push(r);
for (const [t, list] of Object.entries(parType)) {
  md += `### ${t} (${list.length})\n\n`;
  md += list.map((r) => `- ${r.label}  \n  ↳ ${r.source}`).join('\n') + '\n\n';
}

fs.mkdirSync('report', { recursive: true });
fs.writeFileSync('report/graph-coverage.md', md);

console.log('couverture:', Object.fromEntries(Object.entries(by).map(([t, v]) => [t, `${v.c}/${v.t}`])), '| non couverts:', uncovered.length, '| to-generate:', toGenerate.length, `| plan: ${vagues.length} vague(s) de ${TAILLE_VAGUE} → report/graph-coverage.md`);
if (!PLUGIN) console.log('PLUGIN_NAME non défini : priorisation « plugin cible avant socle » inactive.');
