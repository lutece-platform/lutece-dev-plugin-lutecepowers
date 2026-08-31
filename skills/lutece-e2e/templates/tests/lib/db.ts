import mysql from 'mysql2/promise';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`[db] variable ${name} manquante dans .env.local`);
  return v;
}

/** Valide un nom de table ou de colonne destiné à être interpolé dans une requête. */
function ident(name: string): string {
  if (!/^[A-Za-z0-9_$]+$/.test(name)) {
    throw new Error(`[db] identifiant SQL invalide : « ${name} » — lettres, chiffres, _ et $ uniquement`);
  }
  return name;
}

let pool: mysql.Pool | null = null;
let targetLogged = false;

/** Renvoie la cible de connexion sous la forme `user@host:port/base` et la journalise au premier appel. */
export function dbTarget(): string {
  const target = `${required('DB_USER')}@${required('DB_HOST')}:${Number(process.env.DB_PORT || 3306)}/${required('DB_NAME')}`;
  if (!targetLogged) {
    targetLogged = true;
    console.log(`[db] cible : ${target}`);
  }
  return target;
}

function getPool(): mysql.Pool {
  if (!pool) {
    dbTarget();
    pool = mysql.createPool({
      host: required('DB_HOST'),
      port: Number(process.env.DB_PORT || 3306),
      database: required('DB_NAME'),
      user: required('DB_USER'),
      password: required('DB_PASSWORD'),
      connectionLimit: 3,
    });
  }
  return pool;
}

/** Exécute une requête SQL et renvoie les lignes. */
export async function query(sql: string, params: unknown[] = []): Promise<any[]> {
  const [rows] = await getPool().query(sql, params);
  return rows as any[];
}

/** Vrai si la requête renvoie au moins une ligne (assertion d'effet en base). */
export async function exists(sql: string, params: unknown[] = []): Promise<boolean> {
  return (await query(sql, params)).length > 0;
}

/** Renvoie le moteur de stockage (`InnoDB`, `MyISAM`, …) d'une table de la base courante. */
export async function tableEngine(table: string): Promise<string> {
  const rows = await query('SELECT ENGINE AS engine FROM information_schema.tables WHERE table_schema = ? AND table_name = ?', [
    required('DB_NAME'),
    table,
  ]);
  if (rows.length === 0) {
    throw new Error(`[db] table « ${table} » absente de ${dbTarget()}`);
  }
  return String(rows[0].engine ?? '');
}

/** Nombre de lignes d'une table vérifiant `colonne = valeur`. */
async function countWhere(table: string, column: string, value: unknown): Promise<number> {
  const rows = await query(`SELECT COUNT(*) AS n FROM \`${ident(table)}\` WHERE \`${ident(column)}\` = ?`, [value]);
  return Number(rows[0]?.n ?? 0);
}

/**
 * Supprime des lignes table par table, dans l'ordre exact de la liste fournie (enfants d'abord,
 * ligne mère en dernier), et renvoie le nombre total de lignes supprimées. Toute erreur SQL
 * interrompt la séquence et est propagée avec la table fautive.
 */
export async function deleteCascade(order: { table: string; column: string; value: unknown }[]): Promise<number> {
  let total = 0;
  for (const step of order) {
    try {
      const res: any = await query(`DELETE FROM \`${ident(step.table)}\` WHERE \`${ident(step.column)}\` = ?`, [step.value]);
      total += Number(res?.affectedRows ?? 0);
    } catch (e) {
      throw new Error(
        `[db] suppression en cascade interrompue sur ${step.table}.${step.column} = ${String(step.value)} : ${(e as Error).message}`,
      );
    }
  }
  return total;
}

/**
 * Vérifie qu'aucune ligne ne subsiste sur chacune des tables listées et échoue en nommant
 * chaque table encore peuplée avec son compte résiduel.
 */
export async function assertNoResidue(checks: { table: string; column: string; value: unknown }[]): Promise<void> {
  const residues: string[] = [];
  for (const check of checks) {
    const n = await countWhere(check.table, check.column, check.value);
    if (n > 0) residues.push(`${check.table} (${check.column} = ${String(check.value)}) : ${n} ligne(s)`);
  }
  if (residues.length > 0) {
    throw new Error(`[db] résidus après nettoyage sur ${dbTarget()} :\n  - ${residues.join('\n  - ')}`);
  }
}

/**
 * Supprime par `LIKE 'prefixe%'` les lignes d'une **table de travail** (table ne contenant que des
 * données produites par les tests). Refuse un préfixe de moins de 3 caractères. Renvoie le nombre
 * de lignes supprimées.
 */
export async function cleanupByPrefix(table: string, column: string, prefix = 'E2E'): Promise<number> {
  if (typeof prefix !== 'string' || prefix.trim().length < 3) {
    throw new Error(`[db] préfixe de nettoyage « ${String(prefix)} » trop court — 3 caractères minimum exigés sur ${table}.${column}`);
  }
  const res: any = await query(`DELETE FROM \`${ident(table)}\` WHERE \`${ident(column)}\` LIKE ?`, [`${prefix}%`]);
  return Number(res?.affectedRows ?? 0);
}

/**
 * Supprime les lignes dont la colonne vaut exactement `value`, sans `LIKE`. Forme à utiliser sur
 * une **table portant des données réelles** et dès que plusieurs specs travaillent sur la même
 * base. Renvoie le nombre de lignes supprimées.
 */
export async function deleteExact(table: string, column: string, value: unknown): Promise<number> {
  const res: any = await query(`DELETE FROM \`${ident(table)}\` WHERE \`${ident(column)}\` = ?`, [value]);
  return Number(res?.affectedRows ?? 0);
}

/**
 * Exécute `fn` après avoir relevé la valeur de `column` sur la ligne désignée par `key`, puis
 * réécrit cette valeur d'origine dans un `finally`. Forme à utiliser sur une **table de
 * référentiel** : aucune suppression n'est effectuée. Échoue si `key` ne désigne pas
 * exactement une ligne.
 */
export async function withRestore<T>(
  table: string,
  column: string,
  key: { column: string; value: unknown },
  fn: () => Promise<T>,
): Promise<T> {
  const rows = await query(
    `SELECT \`${ident(column)}\` AS saved FROM \`${ident(table)}\` WHERE \`${ident(key.column)}\` = ?`,
    [key.value],
  );
  if (rows.length !== 1) {
    throw new Error(
      `[db] ${table} : ${rows.length} ligne(s) pour ${key.column} = ${String(key.value)} — une seule ligne attendue`,
    );
  }
  const saved: unknown = rows[0].saved;
  try {
    return await fn();
  } finally {
    await query(`UPDATE \`${ident(table)}\` SET \`${ident(column)}\` = ? WHERE \`${ident(key.column)}\` = ?`, [saved, key.value]);
  }
}

/**
 * Exécute `setup`, puis `fn`, puis `teardown` dans un `finally`. Patron destiné aux fixtures
 * bac-à-sable créées par le test lui-même (campagne, entrée de référentiel, fenêtre de dates).
 */
export async function withFixture<T>(setup: () => Promise<void>, teardown: () => Promise<void>, fn: () => Promise<T>): Promise<T> {
  await setup();
  try {
    return await fn();
  } finally {
    await teardown();
  }
}

/**
 * Renvoie une empreinte compacte et comparable d'une table (`table:n=<lignes>:crc=<somme>`),
 * calculée à partir de `COUNT(*)` et de la somme des `CRC32` de chaque ligne. Comparable avant
 * et après une campagne de tests sur une base partagée.
 */
export async function empreinteTable(table: string): Promise<string> {
  const name = ident(table);
  const cols = await query(
    'SELECT column_name AS name FROM information_schema.columns WHERE table_schema = ? AND table_name = ? ORDER BY ordinal_position',
    [required('DB_NAME'), name],
  );
  if (cols.length === 0) {
    throw new Error(`[db] table « ${table} » absente de ${dbTarget()}`);
  }
  const expr = cols.map((c) => `IFNULL(CAST(\`${ident(String(c.name))}\` AS CHAR), '~NULL~')`).join(", '|', ");
  const rows = await query(`SELECT COUNT(*) AS n, COALESCE(SUM(CRC32(CONCAT(${expr}))), 0) AS crc FROM \`${name}\``);
  return `${name}:n=${Number(rows[0]?.n ?? 0)}:crc=${String(rows[0]?.crc ?? 0)}`;
}

/** Purge le verrou anti-brute-force du core pour une IP (défaut : localhost). */
export async function resetLockout(ip = '127.0.0.1'): Promise<void> {
  await query('DELETE FROM core_connections_log WHERE ip_address = ?', [ip]);
}

/** Ferme le pool (à appeler en afterAll). */
export async function closeDb(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
  }
}
