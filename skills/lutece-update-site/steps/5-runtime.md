# Step 5 — Liberty

Codes: SI23, SI25, SI31, SI33.

The files live in `src/main/liberty/config/` and are read by the container, not by the war:

- `server.xml`: the features the site needs (the Lutece ones of the bench `harness/liberty/server.xml` of
  `lutece-e2e` are the reference set), one `<dataSource jndiName="…">` per pool of `db.properties`, credentials in
  `<variable>` elements whose values the environment provides, and a `<library>` whose fileset matches the JDBC
  driver jar the war ships (the core brings `mariadb-java-client`): SI25 compares them.
- The logs reach the platform through OpenTelemetry: the feature `mpTelemetry-2.0` and
  `<mpTelemetry source="message, trace, ffdc"/>` (SI33). The exporter is set by the environment
  (`OTEL_SDK_DISABLED=false`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`), never in the repository.
- A `<variable>` named like a Lutece key wins over every `.properties` file (ordinal 500) (SI31).
- `server.env`: only variable names the runtime reads (`OTEL_SERVICE_NAME`, `OTEL_SDK_DISABLED`,
  `OTEL_EXPORTER_OTLP_ENDPOINT`…); a misspelt name is silently ignored.
- `bootstrap.properties`, `jvm.options`: empty unless the site needs a value, never a secret.

The profile each environment runs (`MP_CONFIG_PROFILE`) is set where the environment is deployed; write it in the
hand-over, one line per environment.
