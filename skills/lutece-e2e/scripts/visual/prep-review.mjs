// Prépare le lot de revue visuelle : construit .artifacts/visual-manifest.json à partir de
// report/screenshots/. Par défaut une capture par libellé (la DERNIÈRE = état final) ;
// VISUAL_ALL=1 conserve toutes les captures.
import fs from 'node:fs';

const dir = 'report/screenshots';
if (!fs.existsSync(dir)) {
  console.error('report/screenshots absent — lancer la suite SANS --reporter override pour peupler les captures.');
  process.exit(1);
}
const files = fs.readdirSync(dir).filter((f) => f.endsWith('.png')).sort();
const keepAll = process.env.VISUAL_ALL === '1';

/** Libellé lisible déduit du nom de fichier (suffixe d'index retiré). */
const label = (f) => f.replace(/-\d+\.png$/, '').replace(/\.png$/, '').replace(/[-_]+/g, ' ').trim();
/** Index de capture porté par le nom de fichier (0 si absent). */
const index = (f) => {
  const m = f.match(/-(\d+)\.png$/);
  return m ? Number(m[1]) : 0;
};

const groupes = new Map();
for (const f of files) {
  const l = label(f);
  const g = groupes.get(l);
  if (g) g.push(f);
  else groupes.set(l, [f]);
}

const items = [];
for (const [l, groupe] of groupes) {
  const tri = [...groupe].sort((a, b) => index(a) - index(b) || a.localeCompare(b));
  if (keepAll) {
    for (const f of tri) {
      items.push({ file: `${dir}/${f}`, label: tri.length > 1 ? `${l} [${index(f)}]` : l });
    }
  } else {
    const dernier = tri[tri.length - 1];
    items.push({ file: `${dir}/${dernier}`, label: l });
  }
}

fs.mkdirSync('.artifacts', { recursive: true });
fs.writeFileSync('.artifacts/visual-manifest.json', JSON.stringify(items, null, 2));

const ecartees = files.length - items.length;
const doublons = [...groupes.entries()].filter(([, g]) => g.length > 1).sort((a, b) => b[1].length - a[1].length);
console.log(`revue visuelle : ${items.length} capture(s) retenue(s) sur ${files.length} — ${ecartees} écartée(s).`);
if (!keepAll && ecartees > 0) {
  console.log(`dédoublonnage par libellé : ${doublons.length} libellé(s) en plusieurs exemplaires, la DERNIÈRE capture (état final) est conservée.`);
  for (const [l, g] of doublons.slice(0, 10)) {
    console.log(`  - "${l}" : ${g.length} captures → ${g.length - 1} écartée(s), conservée ${tail(g)}`);
  }
  if (doublons.length > 10) console.log(`  … ${doublons.length - 10} autre(s) libellé(s).`);
  console.log('VISUAL_ALL=1 pour tout conserver (les variantes intermédiaires ne sont alors PAS écartées).');
}
console.log('confidentialité : ces captures peuvent contenir des données personnelles réelles — ne pas versionner, ne pas transmettre.');

/** Nom du fichier conservé pour un groupe de captures de même libellé. */
function tail(groupe) {
  const tri = [...groupe].sort((a, b) => index(a) - index(b) || a.localeCompare(b));
  return tri[tri.length - 1];
}
