-- Reference rows a plugin bench seeds for its scenarios and protected screens: fixed ids in the 9000 range,
-- self-healing on every dbinit (INSERT … WHERE NOT EXISTS), never touched by the forms fuzzer
-- (scenarios/screens.yaml, protected). One parent (9001), one child (9002), one published item (9001).
INSERT INTO myplugin_parent (id_parent, name, description, role_key, workgroup_key)
SELECT 9001, 'Parent e2e', 'Ligne de reference du banc e2e', 'none', 'all'
WHERE NOT EXISTS (SELECT 1 FROM myplugin_parent WHERE id_parent = 9001);
INSERT INTO myplugin_child (id_child, id_parent, title, id_order)
SELECT 9002, 9001, 'Enfant e2e', 0 WHERE NOT EXISTS (SELECT 1 FROM myplugin_child WHERE id_child = 9002);
INSERT INTO myplugin_myentity (id_myentity, id_child, title, status, date_creation)
SELECT 9001, 9002, 'Entite e2e', 1, NOW() WHERE NOT EXISTS (SELECT 1 FROM myplugin_myentity WHERE id_myentity = 9001);
