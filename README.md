# Lutecepowers

Makes a coding agent work the Lutece 8 way: skills it follows step by step, rules applied to the files it edits,
and scripts that check everything a machine can check. Claude Code, Codex, Cursor, Grok Build and OpenCode.

## Before you start

1. **Linux, or Windows through WSL 2.** Nothing else: not native Windows, not Git Bash. On Windows, from an
   administrator PowerShell: `wsl --install -d Ubuntu-24.04`, then do everything inside Ubuntu.
2. **Keep your projects in the Linux file system** (`~/…`), never under `/mnt/c`.
3. **Install the tools inside Linux** (Ubuntu 24.04):

   ```bash
   sudo apt install git python3-yaml openjdk-21-jdk-headless nodejs curl zip unzip
   curl -s "https://get.sdkman.io" | bash && source "$HOME/.sdkman/bin/sdkman-init.sh" && sdk install maven
   ```

   Maven 3.9 (not 4). On Windows, Docker Desktop with the WSL 2 integration of the distribution ticked, for the e2e bench.
4. **Check the setup:** opening the agent in a Lutece project shows its Lutece level, checks the machine and names what
   is missing, with the fix (a Windows `mvn` on the PATH, a project under `/mnt/c`, line endings git will convert, no Docker). For the full
   list, ask the agent *"run the lutecepowers doctor"*.

## Install

| Agent | Command |
|---|---|
| Claude Code | `/plugin marketplace add lutece-platform/lutece-dev-plugin-lutecepowers` then `/plugin install lutecepowers-v8@lutece-plugins` |
| Codex | `codex plugin marketplace add https://github.com/lutece-platform/lutece-dev-plugin-lutecepowers` then `codex plugin add lutecepowers-v8@lutece-plugins` |
| Cursor | clone the repository, then `cursor-agent --plugin-dir <clone>` |
| Grok Build | `grok plugin install https://github.com/lutece-platform/lutece-dev-plugin-lutecepowers --trust` |
| OpenCode | see [the OpenCode install](docs/how-it-works.md#opencode) |

## How it works

- Open the agent **in your project** (plugin, module, library, site) and say what you want, in your own words.
- The agent does that task and what it needs to pass, nothing wider. It picks the matching skill and follows it.
- Scripts check the work; on Claude Code every edit is checked at once. The agent fixes what its edit breaks and leaves
  the rest of the project as it is.
- **Nothing is committed.** You read the result and commit.

## Updating to Lutece 8 — from any version

- `lutece-update-plugin`: a plugin, a module or a library.
- `lutece-update-site`: a site, a pack or a theme.

Ask for it (*"migrate this plugin to v8"*), or say yes when the agent offers it at the end of another task. It never
starts on its own.

The starting version does not matter: Lutece 3, 5, 7 or an older 8. The checks describe the Lutece 8 target, so every
gap is reported whatever the starting point, and the database follows the plugin's own upgrade scripts from the
version the site recorded. An update is proven on an e2e bench: the artefact before, then after, on the same database.

## Skills

<!-- skills:start -->
| Skill | For |
|---|---|
| `lutece-brainstorming` | Shape a new plugin, feature or screen with you before any code. |
| `lutece-cache` | Add, fix or review a cache in a plugin. |
| `lutece-checkup` | Report the state of a project without changing it. |
| `lutece-e2e` | Give a project an e2e bench that tests every screen in one command. |
| `lutece-elasticdata` | Write or change an Elasticsearch data source module. |
| `lutece-lucene-indexer` | Add Lucene search inside a plugin. |
| `lutece-patterns` | The Lutece 8 code patterns, read before writing code. |
| `lutece-rbac` | Add or review the permissions of a plugin. |
| `lutece-scalability-v8` | Make a plugin run on a cluster, and prove it. |
| `lutece-site-multi-instance` | Configure a site to run as several replicas, and check it. |
| `lutece-solr-indexer` | Write or change a Solr search module. |
| `lutece-update-plugin` | Update a plugin, module or library to Lutece 8, from any version. |
| `lutece-update-site` | Update a site, pack or theme to Lutece 8, from any version. |
| `lutece-update-template-bo` | Convert a back-office template to the core macros. |
| `lutece-update-template-fo` | Convert a front-office template to the core macros. |
| `lutece-v8-review` | Review a project for Lutece 8 compliance, read-only. |
| `lutece-workflow` | Write or change a workflow module. |
<!-- skills:end -->

Details: [how it works](docs/how-it-works.md) (session start, hooks, rules, agents, workflows, known limits).
