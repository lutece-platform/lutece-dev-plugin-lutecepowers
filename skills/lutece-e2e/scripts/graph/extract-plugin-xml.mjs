// Extracteur : plugin.xml → nœuds `view` (features BO via <feature-url>, XPages FO via <application-id>).
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
if (!dir) { console.error('usage: extract-plugin-xml.mjs <plugin-dir>'); process.exit(1); }

const pluginsDir = path.join(dir, 'webapp/WEB-INF/plugins');
let xmls = [];
try {
  xmls = fs.readdirSync(pluginsDir).filter((f) => f.endsWith('.xml')).map((f) => path.join(pluginsDir, f));
} catch { /* pas de dossier plugins */ }

const nodes = [];
const edges = [];
for (const f of xmls) {
  const x = fs.readFileSync(f, 'utf8');
  for (const m of x.matchAll(/<feature-url>([^<]+)<\/feature-url>/g)) {
    const url = m[1].trim();
    nodes.push({ id: `view:${url}`, type: 'view', label: url, source: 'plugin.xml(BO)' });
  }
  for (const m of x.matchAll(/<application-id>([^<]+)<\/application-id>/g)) {
    const app = m[1].trim();
    nodes.push({ id: `view:page=${app}`, type: 'view', label: `FO page=${app}`, source: 'plugin.xml(FO)' });
  }
}
process.stdout.write(JSON.stringify({ nodes, edges }, null, 2));
