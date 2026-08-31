export const meta = {
  name: 'lutece-e2e-generate-tests',
  description: 'Génère en parallèle un test e2e par unité (entité CRUD / nœud du graphe), puis vérifie chaque spec de façon adversariale',
  phases: [
    { title: 'Générer', detail: 'un agent par item : inspecte en live + écrit tests/<name>.spec.ts' },
    { title: 'Vérifier', detail: 'un agent par spec : le lance headless + contrôle effet/réversibilité/faux-vert' },
  ],
}

// args = work-list : [{ name, kind, type?, label?, source?, hints? }]
//   name  : slug stable SANS tiret (sert de suffixe de clé E2E<name> et de nom de fichier)
//   kind  : 'entity' (CRUD via gabarit) | 'node' (vue/action → spec ciblé)
// (tolère args passé comme tableau OU comme chaîne JSON)
const parsed = typeof args === 'string' ? JSON.parse(args) : args
const items = Array.isArray(parsed) ? parsed.filter((x) => x && x.name) : []
if (!items.length) { log('work-list vide — rien à générer'); return { generated: 0, verified: 0, failures: [] } }

const MAX = 12 // cap medium
let list = items
if (list.length > MAX) { log(`⚠️ ${items.length} items > ${MAX} : ce run en traite ${MAX} (relancer pour la suite).`); list = items.slice(0, MAX) }

const GEN_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['file', 'done'],
  properties: {
    file: { type: 'string', description: 'chemin du spec écrit (tests/<name>.spec.ts) ou vide si abandon' },
    done: { type: 'boolean' },
    notes: { type: 'string' },
  },
}
const VER_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['file', 'pass'],
  properties: {
    file: { type: 'string' },
    pass: { type: 'boolean', description: 'le spec passe ET asserte un effet réel, réversible, sans faux-vert' },
    issues: { type: 'string' },
  },
}

const results = await pipeline(
  list,
  (it) => agent(
    `Génère UN test e2e Playwright pour cet item d'un site/plugin Lutèce 8 (projet de tests dans le répertoire courant).\n` +
    `Item : ${JSON.stringify(it)}\n\n` +
    `Procédure : suivre scripts/discover-features.md.\n` +
    `- kind='entity' : inspecter EN LIVE le formulaire (vrais name=, lien/action de suppression, table+colonne via le DAO), ` +
    `choisir le bon gabarit (_entity-crud.spec.ts.tmpl legacy OU _entity-crud-mvc.spec.ts.tmpl MVC), remplir les placeholders.\n` +
    `- kind='node' : écrire un spec ciblé qui atteint la vue/action et asserte un EFFET (pas seulement l'affichage).\n\n` +
    `Contraintes NON négociables : réutiliser tests/lib/ (helpers assertNoError/assertAuthenticated/assertLayout, db, storageState) ; ` +
    `clé de test unique **E2E${it.name}** (alphanumérique, SANS tiret) ; CRUD **réversible** (create puis delete, afterAll cleanup) ; ` +
    `aucun effet de bord non réversible (envoi mail/publication).\n` +
    `INTERDITS ABSOLUS : aucune URL/base/identifiant en dur (utiliser env('X'), jamais process.env.X || 'littéral') ; ` +
    `aucune URL devinée (les entrées se LISENT sur la page ; à défaut test.skip(motif)) ; ` +
    `aucun DoAdminLogout ni purge de session (storageState est partagé, ça casse la spec suivante) ; ` +
    `aucun .catch(()=>{}) autour du nettoyage ; jamais new URL(href, page.url()) (double le context-root).\n` +
    `Écrire le fichier tests/${it.name}.spec.ts (outil Write/Edit). Retourner {file, done, notes}.`,
    { label: `gen:${it.name}`, phase: 'Générer', schema: GEN_SCHEMA }
  ),
  (gen, it) => {
    if (!gen || !gen.done || !gen.file) return { file: (gen && gen.file) || `tests/${it.name}.spec.ts`, pass: false, issues: 'génération abandonnée' }
    return agent(
      `Vérifie de façon ADVERSARIALE le spec généré : ${gen.file} (item ${it.name}).\n` +
      `1) Lance-le seul, headless : npx playwright test ${gen.file} (HEADLESS=1).\n` +
      `2) Lis le code du spec et contrôle qu'il :\n` +
      `   - asserte un EFFET réel (ligne en base via db.exists, pas seulement présence dans la liste UI) ;\n` +
      `   - est RÉVERSIBLE (create puis delete, nettoyage enfants d'abord + assertNoResidue, sans .catch silencieux) ;\n` +
      `   - passe la Response à assertNoError (sans elle, le statut HTTP n'est pas vérifié) ;\n` +
      `   - porte un CONTRÔLE POSITIF (une découverte assertée non vide ; un test de refus prouvant que le cas autorisé passe) ;\n` +
      `   - porte un CONTRÔLE NÉGATIF (l'assertion sait échouer sur une valeur voisine inexistante) ;\n` +
      `   - a une PORTÉE d'assertion juste (pas de toContainText sur body entier, qui passe au vert sur un message d'erreur) ;\n` +
      `   - crée ses PRÉCONDITIONS (fixture bac-à-sable) au lieu de les emprunter à l'état courant ;\n` +
      `   - n'est pas en FAUX-VERT : erreur Lutèce rendue en HTTP 200 (« Technical error », « Startup error », « Page not found »), ` +
      `page d'auth (« Please authenticate yourself »), droit RBAC manquant pris pour une session perdue, ` +
      `succès muet assimilé à un succès, paramètre à valeur vide non émis (Lutèce sert sa vue par défaut), ` +
      `page.request utilisé comme s'il partageait la session du navigateur.\n` +
      `Par défaut, considère pass=false si un doute subsiste. Retourner {file, pass, issues}.`,
      { label: `verify:${it.name}`, phase: 'Vérifier', schema: VER_SCHEMA }
    )
  }
)

const verdicts = results.filter(Boolean)
const verified = verdicts.filter((v) => v.pass)
const failures = verdicts.filter((v) => !v.pass).map((v) => ({ file: v.file, issues: v.issues || '' }))
log(`génération : ${verdicts.length} traités, ${verified.length} verts, ${failures.length} à revoir`)
return { generated: verdicts.length, verified: verified.length, failures }
