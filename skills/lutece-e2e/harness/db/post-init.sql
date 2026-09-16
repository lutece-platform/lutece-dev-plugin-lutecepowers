-- Starter kit: the only thing the generic harness does to the database is make the built-in admin account usable
-- (the schema itself is created by the application's own Liquibase at boot). Everything else — reference rows,
-- restricted accounts, synthetic volume — belongs to the artefact under test, in its own harness/db/seed-<name>.sql.
UPDATE core_admin_user SET reset_password = 0, password_max_valid_date = '2099-01-01 00:00:00' WHERE access_code = 'admin';
