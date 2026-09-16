-- First-init only (docker-entrypoint-initdb.d): lets the bench user read and reset the statement digests.
GRANT SELECT, DROP ON performance_schema.* TO 'lutece'@'%';
FLUSH PRIVILEGES;
