// Dump la couverture depuis le serveur instrumenté (tcpserver:6300) + génère le rapport JaCoCo
// (HTML + XML) sur les jars des plugins Lutèce et leurs sources.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [libdir, sourcesCsv] = process.argv.slice(2);
if (!libdir) { console.error('usage: coverage-report.mjs <libdir WEB-INF/lib> <sources-csv>'); process.exit(1); }

const cli = '.artifacts/jacoco/jacococli.jar';
const exec = '.artifacts/jacoco/jacoco.exec';
fs.mkdirSync('report/jacoco', { recursive: true });

// 1) dump (le serveur reste en vie)
execFileSync('java', ['-jar', cli, 'dump', '--address', 'localhost', '--port', '6300', '--destfile', exec], { stdio: 'inherit' });

// 2) rapport — uniquement les artefacts Lutèce (on ignore les libs tierces)
const jars = fs.readdirSync(libdir)
  .filter((f) => /^(plugin-|module-|lutece-core|library-)/.test(f) && f.endsWith('.jar'))
  .map((f) => path.join(libdir, f));
const args = ['-jar', cli, 'report', exec];
for (const j of jars) args.push('--classfiles', j);
for (const s of (sourcesCsv || '').split(',').map((x) => x.trim()).filter(Boolean)) args.push('--sourcefiles', s);
args.push('--html', 'report/jacoco', '--xml', 'report/jacoco.xml', '--name', 'Lutece e2e coverage');
execFileSync('java', args, { stdio: 'inherit' });
console.log('rapport JaCoCo : report/jacoco/index.html + report/jacoco.xml');
