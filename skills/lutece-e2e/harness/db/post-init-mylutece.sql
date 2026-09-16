-- The front-office account of the bench, for plugin-mylutece + module-mylutece-database (shipped and enabled by
-- default, tools/gen-site.sh). Applied by seed.sh only when the module's tables exist. Login test / testtest;
-- PLAINTEXT is a password format the core's PasswordFactory reads in v7 and v8 alike. The `login_fo` scenario
-- step signs it in.
INSERT IGNORE INTO core_role (role, role_description, workgroup_key) VALUES ('e2e_user', 'Front-office user of the e2e bench', 'all');
INSERT IGNORE INTO mylutece_database_user (mylutece_database_user_id, login, password, name_given, name_family, email, is_active)
VALUES (9000, 'test', 'PLAINTEXT:testtest', 'Test', 'User', 'test@example.com', 1);
INSERT IGNORE INTO mylutece_database_user_role (mylutece_database_user_id, role_key) VALUES (9000, 'e2e_user');
