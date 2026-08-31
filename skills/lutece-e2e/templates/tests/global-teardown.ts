import { query, cleanupByPrefix, closeDb, dbTarget } from './lib/db';

// À remplir à la génération : tables et colonnes portant les libellés de test préfixés.
const TABLES_A_RATISSER: { table: string; column: string }[] = [];

const PREFIXE = 'E2E';

/** Journalise une ligne préfixée par l'étape. */
function journal(message: string): void {
  // eslint-disable-next-line no-console
  console.log(`[teardown] ${message}`);
}

/**
 * Ratisse les lignes dont la colonne déclarée commence par le préfixe de test, sur chacune des
 * tables de TABLES_A_RATISSER, puis ferme le pool. Exécuté une seule fois après tous les tests.
 */
export default async function globalTeardown(): Promise<void> {
  try {
    if (TABLES_A_RATISSER.length === 0) {
      journal('TABLES_A_RATISSER vide — aucun ratissage, fermeture du pool seulement.');
      return;
    }
    journal(`cible : ${dbTarget()} — préfixe « ${PREFIXE} » sur ${TABLES_A_RATISSER.length} table(s).`);
    let total = 0;
    for (const { table, column } of TABLES_A_RATISSER) {
      try {
        const n = await cleanupByPrefix(table, column, PREFIXE);
        total += n;
        journal(`${table}.${column} → ${n} ligne(s) purgée(s)`);
      } catch (e) {
        journal(`${table}.${column} → échec du ratissage : ${(e as Error).message}`);
      }
    }
    journal(`total : ${total} ligne(s) purgée(s).`);
  } finally {
    await closeDb().catch((e: unknown) => journal(`fermeture du pool : ${(e as Error).message}`));
  }
}
