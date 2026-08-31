// Confronte le graphe (Phase 2) à la couverture JaCoCo réelle : pour chaque classe portant des nœuds
// du graphe (JspBean/@Controller), affiche le % de branches/lignes réellement exercé.
import fs from 'node:fs';

if (!fs.existsSync('report/jacoco.xml')) { console.error('report/jacoco.xml absent — lancer coverage-report.mjs'); process.exit(1); }
if (!fs.existsSync('.artifacts/graph.json')) { console.error('.artifacts/graph.json absent — lancer build-graph.mjs'); process.exit(1); }

const xml = fs.readFileSync('report/jacoco.xml', 'utf8');
const cov = {};
for (const m of xml.matchAll(/<class name="([^"]+)"[^>]*>([\s\S]*?)<\/class>/g)) {
  const name = m[1].split('/').pop();
  const b = /type="BRANCH" missed="(\d+)" covered="(\d+)"/.exec(m[2]);
  const l = /type="LINE" missed="(\d+)" covered="(\d+)"/.exec(m[2]);
  cov[name] = { b: b ? { miss: +b[1], cov: +b[2] } : null, l: l ? { miss: +l[1], cov: +l[2] } : null };
}

const g = JSON.parse(fs.readFileSync('.artifacts/graph.json', 'utf8'));
const classes = [...new Set(g.nodes
  .map((n) => (n.source.endsWith('.java') ? n.source.split('/').pop().replace('.java', '') : null))
  .filter(Boolean))].sort();

const pct = (x) => (x && x.cov + x.miss ? Math.round((100 * x.cov) / (x.cov + x.miss)) : 0);
let md = '# Graphe × JaCoCo — couverture réelle par classe (JspBean/@Controller du graphe)\n\n';
let exercised = 0;
for (const c of classes) {
  const v = cov[c];
  if (!v) { md += `- **${c}** : ⚠️ aucune donnée JaCoCo (jamais exercée)\n`; continue; }
  exercised += 1;
  md += `- **${c}** : branches **${pct(v.b)}%** (${v.b?.cov ?? 0}/${v.b ? v.b.cov + v.b.miss : 0}), lignes ${pct(v.l)}%\n`;
}
md += `\n_${exercised}/${classes.length} classes du graphe exercées par la suite e2e._\n`;
fs.writeFileSync('report/graph-vs-jacoco.md', md);
console.log(`confrontation : report/graph-vs-jacoco.md (${exercised}/${classes.length} classes exercées)`);
