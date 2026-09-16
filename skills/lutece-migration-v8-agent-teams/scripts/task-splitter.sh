#!/bin/bash
# task-splitter.sh — Decompose scan.json into per-teammate task assignments
# Usage: bash task-splitter.sh <scan.json> [output_dir]
# Output: tasks-config.json, tasks-java-0.json, ..., tasks-java-homes.json (owned by java-migrator-0), tasks-template.json, tasks-test.json

set -euo pipefail

PLUGIN_ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
PATTERNS_BASE="$PLUGIN_ROOT_DIR/skills/lutece-migration-v8-agent-teams/patterns/"

SCAN_FILE="${1:-.migration/scan.json}"
OUTPUT_DIR="${2:-.migration}"

if [ ! -f "$SCAN_FILE" ]; then
    echo "ERROR: Scan file not found: $SCAN_FILE" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required. Install with: sudo apt install jq" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ─── Read scan data ──────────────────────────────────────

JAVA_TEAMMATES=$(jq -r '.summary.recommendedTeammates.java' "$SCAN_FILE")
TEMPLATE_TEAMMATES=$(jq -r '.summary.recommendedTeammates.template' "$SCAN_FILE")
TEST_TEAMMATES=$(jq -r '.summary.recommendedTeammates.test' "$SCAN_FILE")

echo "=== Task Splitter ==="
echo "Java teammates: $JAVA_TEAMMATES"
echo "Template teammate: $TEMPLATE_TEAMMATES"
echo "Test teammate: $TEST_TEAMMATES"
echo ""

# ─── Config tasks ────────────────────────────────────────

jq '{
  teammate: "config-migrator",
  tasks: {
    pom: {
      description: "Migrate pom.xml: parent = latest released 8.x (project.latestParent), bump version, remove Spring/EhCache/Jersey deps, JPA on the container provider (persistence-patterns.md) when summary.persistence.hasJpa, EL implementation matching the parent, add library-lutece-unit-testing",
      project: .project
    },
    beansXml: {
      description: "Create src/main/resources/META-INF/beans.xml (CDI 4.0, annotated discovery)"
    },
    contextXml: {
      description: "Catalog all Spring context XML beans, output to .migration/context-beans.json, then delete context files",
      files: [.files.contextXml[] | .path]
    },
    pluginDescriptor: {
      description: "Update plugin.xml: remove <application-class>, set min-core-version to 8.0.0, bump version",
      files: ["webapp/WEB-INF/plugins/"]
    },
    webXml: {
      description: "Migrate web.xml namespace: java.sun.com → jakarta.ee"
    },
    sql: {
      description: "Add Liquibase headers to SQL files",
      files: [.files.sql[] | .path]
    },
    properties: {
      description: "Create @ConfigProperty entries for beans needing producer properties"
    }
  },
  dependencies: .dependencies,
  summary: .summary
}' "$SCAN_FILE" > "$OUTPUT_DIR/tasks-config.json"

echo "  Created tasks-config.json"

# ─── Java tasks — partition by package ───────────────────

# Extract non-test, non-interface Java files and sort by package category
# business/ → group 0, service/ → group 1, web/ → group 2, other → distributed

if [ "$JAVA_TEAMMATES" -eq 1 ]; then
    # Single Java teammate: all files in one group
    jq --arg patterns "$PATTERNS_BASE" '{
      teammate: "java-migrator-0",
      files: [.files.java[] | select(.classType != "interface" and .classType != "home")],
      contextBeansFile: ".migration/context-beans.json",
      patternsBase: $patterns
    }' "$SCAN_FILE" > "$OUTPUT_DIR/tasks-java-0.json"
    echo "  Created tasks-java-0.json (all files)"

elif [ "$JAVA_TEAMMATES" -eq 2 ]; then
    # Two teammates: {business + home} and {service + web + other}
    jq --arg patterns "$PATTERNS_BASE" '{
      teammate: "java-migrator-0",
      files: [.files.java[] | select((.classType != "interface" and .classType != "home") and (.package | test("business")))],
      contextBeansFile: ".migration/context-beans.json",
      patternsBase: $patterns
    }' "$SCAN_FILE" > "$OUTPUT_DIR/tasks-java-0.json"

    jq --arg patterns "$PATTERNS_BASE" '{
      teammate: "java-migrator-1",
      files: [.files.java[] | select((.classType != "interface" and .classType != "home") and (.package | test("business") | not))],
      contextBeansFile: ".migration/context-beans.json",
      patternsBase: $patterns
    }' "$SCAN_FILE" > "$OUTPUT_DIR/tasks-java-1.json"
    echo "  Created tasks-java-0.json (business/), tasks-java-1.json (service+web+other)"

elif [ "$JAVA_TEAMMATES" -ge 3 ]; then
    # Three teammates: business/, service/, web+other
    jq --arg patterns "$PATTERNS_BASE" '{
      teammate: "java-migrator-0",
      files: [.files.java[] | select((.classType != "interface" and .classType != "home") and (.package | test("business")))],
      contextBeansFile: ".migration/context-beans.json",
      patternsBase: $patterns
    }' "$SCAN_FILE" > "$OUTPUT_DIR/tasks-java-0.json"

    jq --arg patterns "$PATTERNS_BASE" '{
      teammate: "java-migrator-1",
      files: [.files.java[] | select((.classType != "interface" and .classType != "home") and (.package | test("service")))],
      contextBeansFile: ".migration/context-beans.json",
      patternsBase: $patterns
    }' "$SCAN_FILE" > "$OUTPUT_DIR/tasks-java-1.json"

    jq --arg patterns "$PATTERNS_BASE" '{
      teammate: "java-migrator-2",
      files: [.files.java[] | select((.classType != "interface" and .classType != "home") and ((.package | test("business|service")) | not))],
      contextBeansFile: ".migration/context-beans.json",
      patternsBase: $patterns
    }' "$SCAN_FILE" > "$OUTPUT_DIR/tasks-java-2.json"
    echo "  Created tasks-java-{0,1,2}.json (business/, service/, web+other)"
fi

# ─── Home/Interface files — assign to java-migrator-0 (usually just @Inject updates)

if [ "$(jq '[.files.java[] | select(.classType == "home" or .classType == "interface")] | length' "$SCAN_FILE")" -gt 0 ]; then
  jq '{
    teammate: "java-migrator-0",
    note: "Home and interface files: usually only need import updates, no scope changes",
    homeFiles: [.files.java[] | select(.classType == "home")],
    interfaceFiles: [.files.java[] | select(.classType == "interface")]
  }' "$SCAN_FILE" > "$OUTPUT_DIR/tasks-java-homes.json"
  echo "  Created tasks-java-homes.json"
else
  rm -f "$OUTPUT_DIR/tasks-java-homes.json"
fi

# ─── Template tasks ──────────────────────────────────────

if [ "$TEMPLATE_TEAMMATES" -gt 0 ]; then
    jq --arg patterns "$PATTERNS_BASE" '{
      teammate: "template-migrator",
      adminTemplates: [.files.adminTemplates[]],
      skinTemplates: [.files.skinTemplates[]],
      jspFiles: [.files.jsp[]],
      patternsBase: $patterns
    }' "$SCAN_FILE" > "$OUTPUT_DIR/tasks-template.json"
    echo "  Created tasks-template.json"
fi

# ─── Test tasks ──────────────────────────────────────────

if [ "$TEST_TEAMMATES" -gt 0 ]; then
    jq '{
      teammate: "test-migrator",
      files: [.files.tests[]],
      hasUnitTestingDep: .summary.hasUnitTestingDep,
      usesLuteceTestCase: .summary.usesLuteceTestCase
    }' "$SCAN_FILE" > "$OUTPUT_DIR/tasks-test.json"
    echo "  Created tasks-test.json"
fi

# ─── Summary ─────────────────────────────────────────────

echo ""
echo "=== Task Distribution Summary ==="
echo "  Config: 1 teammate, $(jq '.tasks | keys | length' "$OUTPUT_DIR/tasks-config.json") task groups"

for i in $(seq 0 $((JAVA_TEAMMATES - 1))); do
    if [ -f "$OUTPUT_DIR/tasks-java-$i.json" ]; then
        COUNT=$(jq '.files | length' "$OUTPUT_DIR/tasks-java-$i.json")
        echo "  Java-$i: $COUNT files"
    fi
done

if [ "$TEMPLATE_TEAMMATES" -gt 0 ]; then
    AT=$(jq '.adminTemplates | length' "$OUTPUT_DIR/tasks-template.json")
    ST=$(jq '.skinTemplates | length' "$OUTPUT_DIR/tasks-template.json")
    JSP=$(jq '.jspFiles | length' "$OUTPUT_DIR/tasks-template.json")
    echo "  Template: $AT admin + $ST skin + $JSP JSP"
fi

if [ "$TEST_TEAMMATES" -gt 0 ]; then
    TC=$(jq '.files | length' "$OUTPUT_DIR/tasks-test.json")
    echo "  Test: $TC files"
fi

echo "  Verifier: 1 teammate (continuous verification + build)"
echo ""
echo "Total teammates: $((1 + JAVA_TEAMMATES + TEMPLATE_TEAMMATES + TEST_TEAMMATES + 1))"
