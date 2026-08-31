// Extracteur : JspBeans @Controller → nœuds `view` (@View) et `action` (@Action), constantes résolues.
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
if (!dir) { console.error('usage: extract-controllers.mjs <plugin-dir>'); process.exit(1); }

function walk(d) {
  if (!fs.existsSync(d)) return [];
  return fs.readdirSync(d, { withFileTypes: true })
    .flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]));
}

const javas = walk(path.join(dir, 'src')).filter((f) => f.endsWith('.java'));
const nodes = [];
const edges = [];

for (const f of javas) {
  const s = fs.readFileSync(f, 'utf8');
  if (!/@Controller\s*\(/.test(s)) continue;
  const bean = path.basename(f, '.java');
  const consts = {};
  for (const m of s.matchAll(/static\s+final\s+String\s+([A-Z0-9_]+)\s*=\s*"([^"]+)"/g)) consts[m[1]] = m[2];
  const resolve = (v) => (v.startsWith('"') ? v.slice(1, -1) : (consts[v.split('.').pop()] ?? v));

  for (const m of s.matchAll(/@View\s*\(\s*(?:value\s*=\s*)?([A-Za-z0-9_."]+)/g)) {
    const v = resolve(m[1]);
    nodes.push({ id: `view:${bean}#${v}`, type: 'view', label: `${bean} view ${v}`, source: f });
  }
  for (const m of s.matchAll(/@Action\s*\(\s*(?:value\s*=\s*)?([A-Za-z0-9_."]+)/g)) {
    const a = resolve(m[1]);
    nodes.push({ id: `action:${bean}#${a}`, type: 'action', label: `${bean} action ${a}`, source: f });
    edges.push({ from: `action:${bean}#${a}`, to: `view:${bean}#default`, kind: 'rend' });
  }
}
process.stdout.write(JSON.stringify({ nodes, edges }, null, 2));
