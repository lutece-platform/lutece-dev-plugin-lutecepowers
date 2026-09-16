-- EXAMPLE (not shipped in a bench): how an agent writes a synthetic-volume seed for the target it tests.
-- The technique is generic (MariaDB SEQUENCE engine, idempotent marker row, variables from seed.sh); the TABLES
-- and row counts are specific to the artefact under test — the core fills core_page/core_admin_user, a FAQ plugin
-- would fill its own questions. Copy into a bench as harness/db/seed-<target>.sql and adapt.
-- Synthetic volume for the Lutece core tables. Variables @users @groups @roles @lists @pages come from seed.sh.
-- Rows are generated server-side with the MariaDB SEQUENCE engine (seq_1_to_N): no client round trips.
-- Idempotent: skipped when the marker user e2e_seed exists.

DELIMITER //
CREATE OR REPLACE PROCEDURE e2e_seed_core()
BEGIN
  IF NOT EXISTS (SELECT 1 FROM core_admin_user WHERE access_code = 'e2e_seed') THEN

    INSERT INTO core_admin_user (access_code, last_name, first_name, email, status, password, locale, level_user,
                                 reset_password, accessibility_mode, password_max_valid_date, account_max_valid_date,
                                 nb_alerts_sent, last_login, workgroup_key)
    VALUES ('e2e_seed', 'Seed', 'Marker', 'seed@e2e.local', 1, 'PLAINTEXT:adminadmin', 'fr', 3, 0, 0, '2099-01-01', NULL, 0, NOW(), 'all');

    INSERT INTO core_admin_user (access_code, last_name, first_name, email, status, password, locale, level_user,
                                 reset_password, accessibility_mode, password_max_valid_date, account_max_valid_date,
                                 nb_alerts_sent, last_login, workgroup_key)
    SELECT CONCAT('user', LPAD(seq, 6, '0')), CONCAT('Nom', seq), CONCAT('Prenom', seq % 997),
           CONCAT('user', seq, '@e2e.local'), IF(seq % 20 = 0, 1, 0), 'PLAINTEXT:adminadmin',
           IF(seq % 3 = 0, 'en', 'fr'), seq % 4, 0, 0, '2099-01-01', NULL, 0,
           DATE_SUB(NOW(), INTERVAL seq % 365 DAY), 'all'
    FROM seq_1_to_1000000 WHERE seq <= @users;

    INSERT IGNORE INTO core_admin_workgroup (workgroup_key, workgroup_description)
    SELECT CONCAT('WG_', LPAD(seq, 4, '0')), CONCAT('Groupe de travail ', seq) FROM seq_1_to_100000 WHERE seq <= @groups;

    INSERT IGNORE INTO core_admin_workgroup_user (workgroup_key, id_user)
    SELECT CONCAT('WG_', LPAD(1 + (u.id_user % @groups), 4, '0')), u.id_user
    FROM core_admin_user u WHERE u.access_code LIKE 'user%';

    INSERT IGNORE INTO core_admin_role (role_key, role_description)
    SELECT CONCAT('ROLE_', LPAD(seq, 4, '0')), CONCAT('Rôle RBAC ', seq) FROM seq_1_to_100000 WHERE seq <= @roles;

    INSERT INTO core_admin_role_resource (role_key, resource_type, resource_id, permission)
    SELECT CONCAT('ROLE_', LPAD(seq, 4, '0')), 'PAGE', '*', '*' FROM seq_1_to_100000 WHERE seq <= @roles;

    INSERT IGNORE INTO core_user_role (role_key, id_user)
    SELECT CONCAT('ROLE_', LPAD(1 + (u.id_user % @roles), 4, '0')), u.id_user
    FROM core_admin_user u WHERE u.access_code LIKE 'user%';

    INSERT IGNORE INTO core_role (role, role_description, workgroup_key)
    SELECT CONCAT('page_role_', LPAD(seq, 4, '0')), CONCAT('Rôle de page ', seq), 'all' FROM seq_1_to_100000 WHERE seq <= @roles;

    INSERT INTO core_admin_mailinglist (name, description, workgroup)
    SELECT CONCAT('Liste ', LPAD(seq, 4, '0')), CONCAT('Liste de diffusion synthétique ', seq), 'all'
    FROM seq_1_to_100000 WHERE seq <= @lists;

    INSERT INTO core_admin_mailinglist_filter (id_mailinglist, workgroup, role)
    SELECT id_mailinglist, 'all', CONCAT('ROLE_', LPAD(1 + (id_mailinglist % @roles), 4, '0'))
    FROM core_admin_mailinglist WHERE name LIKE 'Liste %';

    INSERT INTO core_page (id_parent, name, description, date_update, status, page_order, id_template, date_creation,
                           role, code_theme, node_status, image_content, mime_type, meta_keywords, meta_description,
                           id_authorization_node, display_date_update, is_manual_date_update)
    SELECT 1, CONCAT('Page ', LPAD(seq, 5, '0')), CONCAT('Page synthétique ', seq), NOW(), 1, seq, 2, NOW(),
           'none', 'default', 1, '', 'application/octet-stream', NULL, NULL, 1, 0, 0
    FROM seq_1_to_1000000 WHERE seq <= @pages;

  END IF;
END //
DELIMITER ;
CALL e2e_seed_core();
DROP PROCEDURE e2e_seed_core;

-- Keyed reference rows are restored on every run (the forms suite may rename or delete some of them).
INSERT IGNORE INTO core_admin_workgroup (workgroup_key, workgroup_description)
SELECT CONCAT('WG_', LPAD(seq, 4, '0')), CONCAT('Groupe de travail ', seq) FROM seq_1_to_100000 WHERE seq <= @groups;
INSERT IGNORE INTO core_admin_role (role_key, role_description)
SELECT CONCAT('ROLE_', LPAD(seq, 4, '0')), CONCAT('Rôle RBAC ', seq) FROM seq_1_to_100000 WHERE seq <= @roles;
INSERT IGNORE INTO core_role (role, role_description, workgroup_key)
SELECT CONCAT('page_role_', LPAD(seq, 4, '0')), CONCAT('Rôle de page ', seq), 'all' FROM seq_1_to_100000 WHERE seq <= @roles;
UPDATE core_admin_mailinglist SET name = CONCAT('Liste ', LPAD(id_mailinglist, 4, '0')) WHERE name NOT LIKE 'Liste %' AND name NOT LIKE '%e2e%' AND description LIKE 'Liste de diffusion synthétique%';
