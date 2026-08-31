export const meta = {
  name: 'lutece-e2e-visual-review',
  description: 'Revue visuelle IA des captures Playwright : un agent par lot lit les images et renvoie des findings (checklist 12 points)',
  phases: [{ title: 'Review', detail: 'un agent par lot de ~8 captures' }],
}

// args = items de .artifacts/visual-manifest.json : [{ file, label }]
// (tolère args passé comme tableau OU comme chaîne JSON)
const parsed = typeof args === 'string' ? JSON.parse(args) : args
const items = Array.isArray(parsed) ? parsed.filter((x) => x && x.file) : []
if (!items.length) { log('aucune capture — lancer prep-review.mjs d’abord'); return { count: 0, findings: [] } }

const BATCH = 8
const MAX_BATCHES = 10 // cap medium (< 15 agents)
const batches = []
for (let i = 0; i < items.length; i += BATCH) batches.push(items.slice(i, i + BATCH))
if (batches.length > MAX_BATCHES) {
  log(`⚠️ ${items.length} captures → ${batches.length} lots > ${MAX_BATCHES} : seuls les ${MAX_BATCHES} premiers lots sont revus ce run (relancer pour la suite).`)
  batches.length = MAX_BATCHES
}

const FINDINGS_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['severite', 'page', 'constat'],
        properties: {
          severite: { type: 'string', enum: ['info', 'warn', 'bug'] },
          page: { type: 'string', description: 'label de la capture' },
          constat: { type: 'string', description: 'anomalie visuelle, courte et actionnable' },
        },
      },
    },
  },
}

phase('Review')
const checklist = [
  'CSS/thème appliqué (pas de HTML brut)', 'aucune superposition d’éléments',
  'texte non tronqué', 'alignement/grille cohérents', 'images/icônes chargées',
  'rien hors écran (pas de débordement horizontal)', 'cohérence de skin FO (site) / BO (Tabler)',
  'aspect inachevé / placeholder (hero générique, zone en attente)',
  'proportions (élément/bouton disproportionné)', 'densité (page anormalement vide/courte)',
  'contraste apparemment insuffisant (à confirmer par un ratio WCAG calculé, seuil AA 4,5:1)',
  'contenu qui ne devrait pas être là (script en clair, jeton, trace de débogage, texte parasite)',
].map((c, i) => `${i + 1}. ${c}`).join('\n')

const results = await parallel(batches.map((b, bi) => () =>
  agent(
    `Tu es relecteur visuel d'un site/BO Lutèce. Pour CHAQUE capture ci-dessous, **Read l'image** (outil Read) ` +
    `puis évalue-la selon la checklist. Ne signale QUE les anomalies réelles ; une page correcte ne produit aucun finding. ` +
    `Une capture doit être effectivement regardée (ne juge jamais sur le seul nom de fichier).\n\n` +
    `Checklist :\n${checklist}\n\nCaptures du lot :\n${b.map((x) => `- ${x.label} → ${x.file}`).join('\n')}`,
    { label: `review:lot${bi + 1}`, phase: 'Review', schema: FINDINGS_SCHEMA }
  )
))

const findings = results.filter(Boolean).flatMap((r) => (r && r.findings) || [])
const bug = findings.filter((f) => f.severite === 'bug').length
const warn = findings.filter((f) => f.severite === 'warn').length
log(`revue visuelle : ${findings.length} findings (${bug} bug, ${warn} warn) sur ${batches.length} lot(s)`)
return { count: findings.length, bug, warn, findings }
