# Seed d'un utilisateur Front Office de test (mylutece-database)

Pour `fo-login.spec.ts`. Le **hash du mot de passe** est géré par Lutèce → **créer via l'UI BO** est le
plus fiable (Lutèce hash correctement) ; le seed SQL direct exige de reproduire le hash du module.

## Voie recommandée — via le Back Office

1. BO → « Gestion des utilisateurs du site (Database) »
   (`jsp/admin/plugins/mylutece/modules/database/ManageUsers.jsp?plugin_name=mylutece-database`).
2. Créer un utilisateur : login `e2euser`, mot de passe `E2eP@ss1` (respecter la politique de mot de passe),
   nom/prénom `E2E`, email `e2euser@test.local`, **actif**.
3. Lancer : `FO_USER=e2euser FO_PASS='E2eP@ss1' npx playwright test fo-login`.
4. Nettoyage : supprimer l'utilisateur (BO ou SQL `DELETE FROM mylutece_database_user WHERE login='e2euser'`).

## Voie SQL (si le hash est maîtrisé)

Table `mylutece_database_user` (colonnes `login`, `password`, `name_given`, `name_family`, `email`,
`is_active`, …). Le `password` doit être hashé selon l'algorithme configuré du module
(`password.encryption` / PBKDF2). Ne seeder en SQL que si ce hash est reproductible ; sinon, préférer l'UI.

> Politique de mot de passe : certains sites imposent longueur/complexité — adapter `FO_PASS` en conséquence.
