// Construit le graphe de fonctionnalités : exécute les 3 extracteurs sur chaque dossier de plugin,
// fusionne, écrit .artifacts/graph.json.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dirs = process.argv.slice(2);
if (!dirs.length) { console.error('usage: build-graph.mjs <plugin-dir> [<plugin-dir>...]'); process.exit(1); }

const run = (script, d) => JSON.parse(execFileSync('node', [path.join(here, script), d], { encoding: 'utf8', maxBuffer: 1e8 }));

const nodes = new Map();
const edges = new Map();
for (const d of dirs) {
  for (const script of ['extract-plugin-xml.mjs', 'extract-controllers.mjs', 'extract-templates.mjs']) {
    let g;
    try { g = run(script, d); } catch (e) { console.error(`[${script}] échec sur ${d}: ${e.message}`); continue; }
    for (const n of g.nodes) nodes.set(n.id, { ...nodes.get(n.id), ...n });
    for (const e of g.edges) edges.set(`${e.from}|${e.kind}|${e.to}`, e);
  }
}

fs.mkdirSync('.artifacts', { recursive: true });
const graph = { nodes: [...nodes.values()], edges: [...edges.values()] };
fs.writeFileSync('.artifacts/graph.json', JSON.stringify(graph, null, 2));

const byType = {};
for (const n of graph.nodes) byType[n.type] = (byType[n.type] || 0) + 1;
console.log(`graph.json : ${graph.nodes.length} nœuds, ${graph.edges.length} arêtes —`, byType);
