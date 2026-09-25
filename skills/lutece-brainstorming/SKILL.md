---
name: lutece-brainstorming
description: "Use before any creative Lutece work: a new plugin, a new feature, a new screen, or a behaviour change. Explores intent, requirements and design with the user before any implementation. Triggers on 'I want to build', 'add a feature', 'new plugin', 'how should we design'."
---

# Brainstorming — Turning Ideas Into Designs

> **Mandatory trigger:** You MUST use this skill before any creative work — creating features, building components, adding functionality, or modifying behavior. Explore user intent, requirements and design **before** implementation.

## Process Overview

```
Phase 1: Context    → understand project state
Phase 2: Discovery  → ask questions one at a time to refine the idea
Phase 3: Reuse scan → check if existing Lutece modules/plugins already cover the need
Phase 4: Explore    → propose 2-3 approaches with trade-offs
Phase 5: Design     → present design in small validated sections
Phase 6: Document   → write the validated design to docs/plans/
Phase 7: Handoff    → set up for implementation (optional)
```

## Interaction Model

| Situation | Tool |
|-----------|------|
| Yes/No, pick one, pick many | Ask the user (multiple choice) |
| Open-ended input (names, descriptions, context) | Text prompt in conversation |
| Design section validation ("looks right so far?") | Ask the user (multiple choice) with Approve / Needs changes / Go back |

**Rule:** Only ONE question per message. If a topic needs more exploration, break it into multiple questions.

---

## Phase 1 — Understand Project Context

Before asking anything, silently gather context:

1. **Read project structure** — `pom.xml`, `webapp/WEB-INF/conf/plugins/`, existing Java packages
2. **Check recent commits** — `git log --oneline -10` to understand current momentum
3. **Scan existing features** — plugin descriptor XML, existing XPages, JspBeans, services
4. **Identify Lutece version** — v7 (Spring) or v8 (CDI/Jakarta) from dependencies

Store findings internally. Do NOT dump them on the user — use them to ask smarter questions.

---

## Phase 2 — Discovery (One Question at a Time)

Ask questions to understand **purpose, constraints, and success criteria**.

### Question priorities

1. **What** — What does this feature do? What problem does it solve?
2. **Who** — Back-office users? Front-office visitors? Both? API consumers?
3. **Where** — New plugin? Existing plugin extension? Module?
4. **Scope** — What is explicitly OUT of scope? (Apply YAGNI ruthlessly)
5. **Constraints** — Must integrate with existing workflows? RBAC requirements? Performance targets?
6. **Data** — New business objects? Relationships to existing entities? Parent-child?

### Example question flow

**Message 1:**
```
Ask the user (multiple choice):
  question: "What type of component are you building?"
  options:
    - "New plugin from scratch"
    - "New feature in an existing plugin"
    - "Module extending another plugin"
    - "XPage (front-office functionality)"
```

**Message 2** (adapts based on answer):
```
Ask the user (multiple choice):
  question: "Who will use this feature?"
  options:
    - "Back-office administrators only"
    - "Front-office visitors only"
    - "Both back-office and front-office"
    - "REST API consumers"
```

**Message 3** (open-ended when needed):
```
Can you describe in a few words what this feature should do?
What problem does it solve for users?
```

Continue until you have enough clarity to propose approaches. Typically 4-8 questions.

---

## Phase 3 — Reuse Scan (Existing Modules Check)

> **Before building anything, check if Lutece already has it.** Many features exist as plugins or modules on lutece-platform or lutece-secteur-public. Reusing or extending an existing module is always preferable to building from scratch.

### Where to search

| Source | What to look for | How |
|--------|-----------------|-----|
| **Lutece Platform GitHub** | Official plugins and modules | Search the web for `site:github.com/lutece-platform [feature keywords]` |
| **Lutece Secteur Public GitHub** | Public-sector-specific modules | Search the web for `site:github.com/lutece-secteur-public [feature keywords]` |
| **Local references** | Already-cloned v8 repos | Search the references in `~/.lutece-references/` |
| **Lutece dev wiki** | Architecture notes, existing module docs | Search the web for `site:dev.lutece.paris.fr [feature keywords]` |
| **Maven artifacts** | Published Lutece modules | Search for `fr.paris.lutece.plugins` + keywords |

### Search strategy

1. **Identify keywords** from the Discovery phase (e.g. "notification", "workflow", "form", "directory", "appointment")
2. **Search GitHub orgs** — search the web in both `lutece-platform` and `lutece-secteur-public`:
   ```
   site:github.com/lutece-platform [keyword] plugin OR module
   site:github.com/lutece-secteur-public [keyword] module
   ```
3. **Check local references** — scan `~/.lutece-references/` for related code
4. **Read README / plugin descriptor** of any promising match to assess fit

### Present findings to user

If matches are found, present them:

```markdown
## Existing Modules Found

### module-xyz (lutece-platform)
- **Repo:** github.com/lutece-platform/lutece-xyz-module-abc
- **What it does:** [1-2 sentences]
- **Covers your need?** Fully / Partially / Tangentially
- **Lutece 8 ready?** Yes / Needs migration

### plugin-abc (lutece-secteur-public)
- **Repo:** github.com/lutece-secteur-public/lutece-abc-plugin-def
- **What it does:** [1-2 sentences]
- **Covers your need?** Fully / Partially / Tangentially
- **Lutece 8 ready?** Yes / Needs migration
```

Then ask:

```
Ask the user (multiple choice):
  question: "How do you want to proceed?"
  options:
    - "Use [module-xyz] as-is (just integrate it)"
    - "Extend [module-xyz] to add what's missing"
    - "Build from scratch (none of these fit)"
    - "I need more details on one of these modules"
```

If **"Use as-is"** → skip to Phase 6 (Document) with an integration plan instead of a full design.
If **"Extend"** → Phase 4 & 5 focus on the extension only, not a full build.
If **"Build from scratch"** → continue normally to Phase 4.
If **"More details"** → fetch the module's README, plugin descriptor, and key source files, then re-ask.

### If nothing found

Briefly inform the user:

> No existing Lutece plugin or module found for this need on lutece-platform or lutece-secteur-public. We'll design it from scratch.

Then proceed to Phase 4.

---

## Phase 4 — Explore Approaches (Build vs Extend)

Propose **2-3 different approaches** with trade-offs. Lead with your recommendation.

### Format

```markdown
## Approach A — [Name] (Recommended)

**How it works:** [2-3 sentences]
**Pros:** [bullet list]
**Cons:** [bullet list]
**Fits Lutece patterns:** [which existing patterns this follows]

## Approach B — [Name]

**How it works:** [2-3 sentences]
**Pros:** [bullet list]
**Cons:** [bullet list]

## Approach C — [Name] (if applicable)

**How it works:** [2-3 sentences]
**Pros:** [bullet list]
**Cons:** [bullet list]
```

Then ask:

```
Ask the user (multiple choice):
  question: "Which approach do you prefer?"
  options:
    - "Approach A — [Name] (Recommended)"
    - "Approach B — [Name]"
    - "Approach C — [Name]"
```

If the user picks "Other", explore their alternative before continuing.

### Lutece-specific considerations

When proposing approaches, evaluate against:

- **Existing Lutece patterns** — consult `~/.lutece-references/` for real implementations
- **Plugin descriptor constraints** — what the XML descriptor supports
- **CDI scope implications** — `@ApplicationScoped` vs `@Dependent` vs `@RequestScoped`
- **DAO/Home layer conventions** — see `/lutece-dao` skill
- **Template conventions** — Freemarker macros, admin theme, front-office skin
- **Workflow integration** — does this need workflow states?
- **RBAC** — does this need permission management?
- **Cache** — does this benefit from caching?

---

## Phase 5 — Present the Design

Once the approach is chosen, present the design **in sections of 200-300 words**. After each section, validate with the user.

### Section order

1. **Architecture overview** — layers, components, data flow diagram
2. **Business objects** — entities, fields, relationships
3. **DAO / Home layer** — persistence strategy, SQL queries
4. **Service layer** — business logic, CDI beans, scopes
5. **Web layer** — JspBeans (back-office) and/or XPages (front-office)
6. **Templates** — admin HTML templates, front-office Freemarker
7. **Plugin descriptor** — XML entries needed
8. **Error handling & validation** — user input validation, error messages
9. **i18n** — `messages.properties` keys
10. **Testing strategy** — unit tests, integration points

> Skip sections that don't apply. Not every feature needs all 10 sections.

### After each section

```
Ask the user (multiple choice):
  question: "Does this section look right?"
  options:
    - "Looks good, continue"
    - "Needs changes (I'll explain)"
    - "Go back to a previous section"
```

If "Needs changes", ask what to change, revise, and re-validate before moving on.

---

## Phase 6 — Document the Design

Once all sections are validated:

1. **Create the design document:**

   ```
   docs/plans/YYYY-MM-DD-<topic>-design.md
   ```

   Structure:
   ```markdown
   # Design: [Feature Name]

   **Date:** YYYY-MM-DD
   **Status:** Draft | Approved
   **Plugin:** [plugin-name]
   **Lutece version:** 8.x

   ## Context
   [Problem statement, 2-3 sentences]

   ## Decision
   [Chosen approach and rationale]

   ## Design
   [All validated sections from Phase 5]

   ## Files to Create/Modify
   [Checklist of files with what each one needs]

   ## Out of Scope
   [Explicitly excluded items]
   ```

2. **Do not commit.** Tell the user the file path. The user decides when and how to commit.

---

## Phase 7 — Handoff to Implementation (Optional)

```
Ask the user (multiple choice):
  question: "Ready to set up for implementation?"
  options:
    - "Yes, let's start implementing"
    - "Not yet, I want to review the design first"
    - "No, just the design for now"
```

If yes:

1. **Relevant skills** — point to the skills needed for implementation:
   - `/lutece-dao` for DAO/Home layer
   - `/lutece-patterns` for architecture patterns
   - `/lutece-workflow` if workflow integration is needed
   - `/lutece-rbac` if RBAC is needed
   - `/lutece-cache` if caching is needed
2. **Create a task list** — use your task-tracking tool to break the design into implementation tasks

---

## Key Principles

| Principle | Rule |
|-----------|------|
| **One question at a time** | Never overwhelm with multiple questions in one message |
| **Multiple choice preferred** | Easier to answer than open-ended when possible |
| **YAGNI ruthlessly** | Remove unnecessary features from all designs |
| **Explore alternatives** | Always propose 2-3 approaches before settling |
| **Incremental validation** | Present design in sections, validate each one |
| **Be flexible** | Go back and clarify when something doesn't make sense |
| **Reuse-first** | Search lutece-platform and lutece-secteur-public for existing modules before building |
| **Lutece-first** | Always check `~/.lutece-references/` for existing patterns before inventing |
| **Context before questions** | Read the project state silently before asking anything |
