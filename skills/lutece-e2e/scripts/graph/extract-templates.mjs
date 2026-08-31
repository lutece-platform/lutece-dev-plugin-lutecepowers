// Extracteur : templates FreeMarker → nœuds `form` (<@tform>/<form>) et `list-control` (<@button>/<@aButton>),
// avec le compte de branches (#if/#list).
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
if (!dir) { console.error('usage: extract-templates.mjs <plugin-dir>'); process.exit(1); }

function walk(d) {
  if (!fs.existsSync(d)) return [];
  return fs.readdirSync(d, { withFileTypes: true })
    .flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]));
}

const tpls = walk(path.join(dir, 'webapp/WEB-INF/templates')).filter((f) => f.endsWith('.html'));
const nodes = [];

for (const f of tpls) {
  const s = fs.readFileSync(f, 'utf8');
  const base = path.basename(f);
  const forms = (s.match(/<@tform|<form\b/g) || []).length;
  const buttons = (s.match(/<@aButton|<@button/g) || []).length;
  const branches = (s.match(/<#if|<#list/g) || []).length;
  if (forms) {
    nodes.push({ id: `form:${base}`, type: 'form', label: `form ${base}`, source: f, meta: { branches: String(branches), buttons: String(buttons) } });
  }
  if (buttons) {
    nodes.push({ id: `list-control:${base}`, type: 'list-control', label: `contrôles ${base}`, source: f, meta: { buttons: String(buttons), branches: String(branches) } });
  }
}
process.stdout.write(JSON.stringify({ nodes, edges: [] }, null, 2));
