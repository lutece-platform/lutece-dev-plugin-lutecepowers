# Default install status (seeds the datastore on first boot via loadPluginsStatus).
# Default if absent = NOT installed. We enable the plugin under test + its dependencies.
# gen-test-site.sh adds one "<plugin>.installed=1" line per plugin to enable.
@@PUT_PLUGINS_ENABLED@@
