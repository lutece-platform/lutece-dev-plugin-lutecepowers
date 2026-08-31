// Mode incrémental (delta) : à partir d'un diff git, liste les fonctionnalités IMPACTÉES via le graphe,
// distingue celles NON couvertes (à générer) de celles déjà couvertes (à vérifier), et signale les tests
// existants potentiellement CADUCS (référencent un token supprimé par le diff). Ne modifie rien.
//
// usage : changed-features.mjs <repo> [base=develop] [testsDir=tests]
//   <base> accepte une réf (develop, HEAD, un SHA) ou une plage (A...B).
//   Prérequis : .artifacts/graph.json (lancer build-graph.mjs sur <repo> d'abord).
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [repo, base = 'develop', testsDir = 'tests'] = process.argv.slice(2);
if (!repo) { console.error('usage: changed-features.mjs <repo> [base=develop] [testsDir=tests]'); process.exit(1); }

const git = (args) => execFileSync('git', ['-C', repo, ...args], { encoding: 'utf8', maxBuffer: 1e8 });

// 1) Fichiers changés (repo-relatifs) : diff working-tree vs base (ou plage A...B) + fichiers non suivis.
let changed = [];
try {
  changed = git(['diff', '--name-only', base]).split('\n').filter(Boolean);
  const untracked = git(['ls-files', '--others', '--exclude-standard']).split('\n').filter(Boolean);
  changed = [...new Set([...changed, ...untracked])];
} catch (e) {
  console.error(`Échec git (repo=${repo}, base=${base}) : ${e.message}\n` +
    '→ vérifier que <repo> est un dépôt git et que <base> existe (ex. `git fetch origin develop`).');
  process.exit(1);
}
const changedSet = new Set(changed);

// 2) Charger le graphe du code courant.
if (!fs.existsSync('.artifacts/graph.json')) {
  console.error(`graph.json absent — lancer d'abord :\n  node <skill>/scripts/graph/build-graph.mjs ${repo}`);
  process.exit(1);
}
const g = JSON.parse(fs.readFileSync('.artifacts/graph.json', 'utf8'));

// 3) Nœuds impactés : un fichier changé est un suffixe de chemin de node.source.
const norm = (p) => p.replace(/\\/g, '/');
const isPathSource = (s) => typeof s === 'string' && s.includes('/');
const suffixMatch = (source) => {
  const src = norm(source);
  return changed.some((f) => {
    const cf = norm(f);
    return src === cf || src.endsWith('/' + cf) || src.endsWith(cf);
  });
};
const impacted = g.nodes.filter((n) => isPathSource(n.source) && suffixMatch(n.source));
const pluginXmlChanged = changed.some((f) => /plugin\.xml$/.test(f));

// 4) Couverture (même heuristique approximative que coverage-map.mjs).
const readJson = (p) => (fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, 'utf8')) : []);
const specTexts = fs.existsSync(testsDir)
  ? fs.readdirSync(testsDir).filter((f) => f.endsWith('.spec.ts')).map((f) => ({ file: `${testsDir}/${f}`, text: fs.readFileSync(`${testsDir}/${f}`, 'utf8') }))
  : [];
const hay = [
  ...readJson('.artifacts/urls-fo.json'),
  ...readJson('.artifacts/urls-bo.json').map((x) => x.url || x),
  ...specTexts.map((s) => s.text),
].join('\n').toLowerCase();
const term = (n) => n.id.split(':').pop().split('#').pop().replace(/\.(html|jsp)$/i, '').toLowerCase();
const covered = (n) => term(n).length > 2 && hay.includes(term(n));

const toGenerate = impacted.filter((n) => !covered(n));
const toVerify = impacted.filter((n) => covered(n));

// 5) Tests caducs : tokens supprimés par le diff (présents en '-' et absents des '+') référencés par un spec.
let removedTokens = new Set();
let keptTokens = new Set();
try {
  const diff = git(['diff', base, '--', '*.java', '*.html', '*.jsp', '*.ftl']);
  const grab = (line, bucket) => {
    for (const re of [
      /\b([A-Za-z][A-Za-z0-9_]*\.jsp)\b/g,
      /@View\s*\(\s*(?:value\s*=\s*)?"([^"]+)"/g,
      /@Action\s*\(\s*(?:value\s*=\s*)?"([^"]+)"/g,
      /[?&](?:view|action)=([A-Za-z0-9_]+)/g,
      /name\s*=\s*"([A-Za-z0-9_]+)"/g,
    ]) for (const m of line.matchAll(re)) bucket.add(m[1]);
  };
  for (const line of diff.split('\n')) {
    if (/^-[^-]/.test(line)) grab(line, removedTokens);
    else if (/^\+[^+]/.test(line)) grab(line, keptTokens);
  }
} catch { /* diff des sources indisponible : section caducs vide */ }
// Réellement retiré = supprimé ET non ré-ajouté ailleurs dans le diff.
const trulyRemoved = [...removedTokens].filter((t) => !keptTokens.has(t) && t.length > 2);
const stale = [];
for (const s of specTexts) for (const t of trulyRemoved) {
  if (new RegExp(`\\b${t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`).test(s.text)) stale.push({ spec: s.file, token: t });
}

// 6) Changements non mappés (ni nœud impacté, ni plugin.xml) — pour info.
const mappedFiles = new Set(impacted.map((n) => norm(n.source)));
const unmapped = changed.filter((f) => ![...mappedFiles].some((m) => m.endsWith(norm(f))) && !/plugin\.xml$/.test(f));

// Rapport.
const uniq = (arr) => [...new Map(arr.map((x) => [JSON.stringify(x), x])).values()];
let md = `# Couverture des changements (mode delta)\n\n`;
md += `> Base : \`${base}\` · repo : \`${repo}\` · ⚠️ mapping/couverture approximatifs (recouper JaCoCo).\n\n`;
md += `- Fichiers changés : **${changed.length}**\n`;
md += `- Nœuds impactés : **${impacted.length}** (à générer : **${toGenerate.length}**, à vérifier : **${toVerify.length}**)\n`;
md += `- Tests possiblement caducs : **${uniq(stale).length}**\n`;
if (pluginXmlChanged) md += `- ⚠️ un \`plugin.xml\` a changé → revérifier la liste des features BO/FO (nœuds \`view\`).\n`;
md += `\n## À générer (impacté, non couvert)\n\n`;
md += toGenerate.length ? toGenerate.map((n) => `- [${n.type}] ${n.label}\n  ↳ ${n.source}`).join('\n') + '\n' : '_aucun_\n';
md += `\n## À vérifier (impacté, déjà couvert — confirmer que le test couvre le NOUVEAU comportement)\n\n`;
md += toVerify.length ? toVerify.map((n) => `- [${n.type}] ${n.label}\n  ↳ ${n.source}`).join('\n') + '\n' : '_aucun_\n';
md += `\n## Tests possiblement caducs (token supprimé — à revoir MANUELLEMENT, non modifiés)\n\n`;
md += uniq(stale).length ? uniq(stale).map((x) => `- \`${x.spec}\` référence \`${x.token}\` (supprimé du code)`).join('\n') + '\n' : '_aucun_\n';
md += `\n## Changements non mappés à un nœud (DAO/business/config — test unitaire éventuel)\n\n`;
md += unmapped.length ? unmapped.map((f) => `- ${f}`).join('\n') + '\n' : '_aucun_\n';

fs.mkdirSync('report', { recursive: true });
fs.writeFileSync('report/delta-coverage.md', md);

// Work-list machine (alimente workflows/generate-tests.js) : nœuds impactés non couverts.
const lastTok = (s) => (s.trim().split(/\s+/).pop() || s);
const slug = (s) => s.replace(/[^a-z0-9]+/gi, '').slice(0, 28) || 'node';
const nodeName = (n) => slug(`${n.type}${lastTok(n.label)}`); // token distinctif (nom de vue/action)
const seenNames = new Set();
const workList = toGenerate.map((n) => {
  let name = nodeName(n); let i = 1;
  while (seenNames.has(name)) { name = `${nodeName(n)}${i++}`; }
  seenNames.add(name);
  return { name, kind: n.type === 'entity' ? 'entity' : 'node', type: n.type, label: n.label, source: n.source };
});
fs.mkdirSync('.artifacts', { recursive: true });
fs.writeFileSync('.artifacts/to-generate.json', JSON.stringify(workList, null, 2));

console.log(`delta: ${changed.length} fichiers changés | impactés ${impacted.length} (générer ${toGenerate.length}, vérifier ${toVerify.length}) | caducs ${uniq(stale).length} | to-generate ${workList.length} → report/delta-coverage.md`);
