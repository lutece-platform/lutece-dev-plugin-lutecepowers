#!/usr/bin/env python3
"""Turns the run artifacts into two reports:
  artifacts/summary.md   compact, for humans and agents alike (totals, failures with one-line causes, slowest
                         screens, console noise, SQL hot spots, JFR hot methods) — the file to read first;
  artifacts/report.html  the page for the person who reviews the bench: scenarios by title and steps, screens by
                         feature and view, failures first, technical material under a fold (rendered by report_page.py).
Inputs: artifacts/results/*.jsonl (tests), perf.json, discovered.json, inventory.json, junit-*.xml presence."""
import datetime
import html
import json
import pathlib
import re
import statistics

import report_page

E2E = pathlib.Path(__file__).resolve().parents[1]
A = E2E / "artifacts"
BUDGET_MS = 1500
"""Per-screen navigation budget (browser-measured, small volume) flagged in the summary."""


def per_row(top, navigations):
    """SQL SELECTs played far more often than the bench opened pages: a query run once per row.

    The denominator is the number of navigations, not HTTP requests, because static assets would drown the
    ratio. Writes are excluded: a bulk insert is legitimately repeated. The ratio is the mechanical signal;
    naming the loop stays the agent's job.
    """
    if not navigations:
        return []
    out = [(t, t["count"] / navigations) for t in top
           if t.get("count", 0) >= 500 and t["count"] >= 10 * navigations
           and t.get("sql", "").lstrip().upper().startswith("SELECT")]
    return sorted(out, key=lambda x: -x[0]["count"])[:6]


def load_results():
    rows = []
    for f in sorted((A / "results").glob("*.jsonl")) if (A / "results").exists() else []:
        for line in f.read_text().splitlines():
            if line.strip():
                rows.append(json.loads(line))
    return rows


def js(p):
    try:
        return json.loads((A / p).read_text())
    except Exception:  # noqa: BLE001
        return {}


def target_matcher(cov, inv):
    """Predicate telling whether a test result belongs to the artefact under test: one of its visited urls is an
    inventory element of origin target, or lives under a plugin directory / front-office page of that artefact."""
    paths = {x["url"].split("?")[0] for k in ("screens", "actions") for x in cov.get(k, []) if x.get("origin", "target") == "target"}
    names = {f.get("plugin") for f in inv.get("features", []) if f.get("origin", "target") == "target"} - {None, "core"}
    marks = [("/plugins/%s/" % n) for n in names] + [("page=%s" % n) for n in names]
    if not any(x.get("origin") == "env" for k in ("screens", "actions") for x in cov.get(k, [])):
        return lambda r: True

    def is_target(r):
        urls = [r.get("url") or "", r.get("screen") or "", r.get("action") or ""] + list(r.get("visited") or [])
        return any(u.split("?")[0] in paths or any(m in u for m in marks) for u in urls if u) or r["suite"] == "scenarios"
    return is_target


def summary(rows, perf, disc, inv):
    by_suite = {}
    for r in rows:
        by_suite.setdefault(r["suite"], []).append(r)
    L = ["# Rapport e2e — %s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), ""]
    rv = A / "review.md"
    todo = A / "review-todo.md"
    if todo.exists():
        n = len(re.findall(r"^\| G\d{3} ", todo.read_text(), re.M))
        done = len(set(re.findall(r"\bG\d{3}\b", rv.read_text()))) if rv.exists() else 0
        L += ["> **Revue visuelle : %s** — %d/%d familles d'écrans jugées (charte, mise en page, cohérence). "
              "Liste : `artifacts/review-todo.md`, verdicts : `artifacts/review.md`."
              % ("faite" if done >= n and n else "À FAIRE", done, n), ""]
    if (A / "INVARIANT-BROKEN.txt").exists():
        L += ["> **INVARIANT DU BANC ROMPU** : " + (A / "INVARIANT-BROKEN.txt").read_text().strip(), ""]
    cov = js("coverage.json")
    fp = js("fingerprint.json")
    if fp:
        L.append("Testé : sources `%s`%s, war `%s`%s." % (fp.get("source_commit") or "?", " (modifications non commitées)" if fp.get("source_dirty") else "",
                 fp.get("war_sha256") or "-", (", instance `%s`" % fp["base_url"]) if fp.get("base_url") else ""))
    # The perimeter first, the whole site after: the reader must not carry away the site's count as the plugin's.
    st_t = (cov.get("stats_target") or {}) if cov else {}
    if st_t and any(x.get("origin") == "env" for k in ("screens", "actions") for x in cov.get(k, [])):
        L.append("Périmètre %s : %d écrans, %d actions (le site assemblé en compte %d et %d, hors périmètre). %d écrans concrets découverts, %d formulaires."
                 % (pathlib.Path(inv.get("root", "")).name, st_t["screens"]["total"], st_t["actions"]["total"],
                    inv.get("stats", {}).get("screens", 0), inv.get("stats", {}).get("actions", 0),
                    disc.get("stats", {}).get("screens", 0), disc.get("stats", {}).get("forms", 0)))
    else:
        L.append("Inventaire : %d fonctionnalités, %d écrans, %d actions (statique) ; %d écrans concrets découverts, %d formulaires."
                 % (inv.get("stats", {}).get("features", 0), inv.get("stats", {}).get("screens", 0), inv.get("stats", {}).get("actions", 0),
                    disc.get("stats", {}).get("screens", 0), disc.get("stats", {}).get("forms", 0)))
    L += ["", "| Suite | Tests | OK | Échecs | Durée |", "|---|---|---|---|---|"]
    for s, rs in by_suite.items():
        ko = [r for r in rs if r["status"] not in ("passed", "skipped")]
        sk = [r for r in rs if r["status"] == "skipped"]
        note = (" %d ignorés" % len(sk)) if sk else ""
        if sk and len(sk) == len(rs):
            # Same rule as run.sh skipped_suites: a fully skipped suite is a hole only when the inventory gave it something to prove.
            tgt = [x for x in inv.get("screens", []) if x.get("origin", "target") == "target"]
            needed = {"fo": any(x.get("surface") == "fo" for x in tgt), "screens": any(x.get("surface", "bo") == "bo" for x in tgt),
                      "forms": any(x.get("surface", "bo") == "bo" for x in tgt)}.get(s, True)
            note = " **suite entièrement ignorée : rien de prouvé**" if needed else " (rien à prouver pour ce périmètre)"
        L.append("| %s | %d | %d | %d | %.0f s |" % (s, len(rs), len(rs) - len(ko) - len(sk), len(ko), sum(r["duration_ms"] for r in rs) / 1000) + note)
    is_target = target_matcher(cov, inv)
    scoped = bool(cov) and any(x.get("origin") == "env" for k in ("screens", "actions") for x in cov.get(k, []))
    if cov:
        st = cov.get("stats_target") or cov["stats"]
        L += ["", "## Couverture de l'inventaire" + (" — périmètre : %s" % pathlib.Path(inv.get("root", "")).name if scoped else ""), ""]
        L += ["", "| | Total | Prouvés (scénario vert) | Défaut (rouge, appel correct) | Robustesse seule (rouge sans paramètres) | Atteints sans preuve | Bloqués par un défaut testé | Inatteignables / hors banc | À faire |", "|---|---|---|---|---|---|---|---|---|"]
        for kind, label in (("screens", "Écrans"), ("actions", "Actions")):
            t = st[kind]
            L.append("| %s | %d | %d | %d | %d | %d | %d | %d | %d |" % (label, t["total"], t.get("n_proven", 0), t.get("n_defect", 0), t.get("n_robustness", 0), t.get("n_reached", 0), t.get("n_blocked", 0), t.get("n_unreachable", 0), t.get("n_todo", 0)))
        L.append("")
        L.append("Une erreur est un test : un élément atteint par un test rouge compte comme testé avec défaut. Un élément « bloqué » est injouable tant que le défaut nommé n'est pas corrigé.")
        tgt = {k: [x for x in cov[k] if (not scoped or x.get("origin", "target") == "target") and x.get("surface", "bo") == "bo"] for k in ("screens", "actions")}
        fo = {k: [x for x in cov[k] if x.get("origin", "target") == "target" and x.get("surface") == "fo"] for k in ("screens", "actions")}
        for kind in ("screens", "actions"):
            missing = [x["url"] for x in tgt[kind] if not x["covered"] and not x.get("excluded")]
            if missing:
                L.append("- %s à couvrir (%d) : %s" % (kind, len(missing), ", ".join("`%s`" % m for m in missing[:40])))
        if scoped:
            env = cov["stats_env"]
            L.append("- environnement (core et autres plugins du site, hors périmètre) : %d écrans dont %d en défaut, %d actions ; ses défauts sont listés à part plus bas."
                     % (env["screens"]["total"], env["screens"]["n_defect"] + env["screens"]["n_robustness"], env["actions"]["total"]))
        sfo = cov.get("stats_fo", {})
        if sfo and (sfo["screens"]["total"] or sfo["actions"]["total"]):
            L += ["", "### Front-office (pages XPage, périmètre)", "",
                  "| | Total | Prouvés | Défaut | Robustesse | Atteints sans preuve | À faire |", "|---|---|---|---|---|---|---|"]
            for kind, label in (("screens", "Pages"), ("actions", "Actions")):
                t = sfo[kind]
                L.append("| %s | %d | %d | %d | %d | %d | %d |" % (label, t["total"], t.get("n_proven", 0), t.get("n_defect", 0), t.get("n_robustness", 0), t.get("n_reached", 0), t.get("n_todo", 0)))
            fo_todo = [x["url"] for x in fo["screens"] if not x["covered"] and not x.get("excluded")]
            if fo_todo:
                L.append("- pages FO à couvrir (%d) : %s" % (len(fo_todo), ", ".join("`%s`" % m for m in fo_todo[:20])))
        L += ["", "### Dette (visible, jamais soustraite)", ""]
        cov = dict(cov, screens=tgt["screens"], actions=tgt["actions"])
        weak = [x["url"] for x in cov["actions"] if x["covered"] and not x.get("proven")]
        if weak:
            L.append("- actions atteintes sans preuve d'état (%d) : %s" % (len(weak), ", ".join("`%s`" % w for w in weak[:40])))
        for kind in ("screens", "actions"):
            blocked = [x for x in cov[kind] if x.get("status") == "blocked"]
            if blocked:
                L.append("- %s bloqués par un défaut testé (%d) : %s" % (kind, len(blocked), ", ".join("`%s` ⇐ %s" % (x["url"], x["blocked_by"]) for x in blocked)))
            unreachable = [x for x in cov[kind] if x.get("status") == "unreachable"]
            if unreachable:
                L.append("- %s inatteignables ou hors banc (%d) : %s" % (kind, len(unreachable), "; ".join("`%s` — %s" % (x["url"], (x["excluded"] or "")[:90]) for x in unreachable)))
    kinds = {}
    for r in rows:
        # The harness suite visits a 404 and an error page on purpose: its kinds would trip the guard below.
        # A scenario made of http steps only never navigates: its page stays blank by construction.
        if r["status"] == "passed" and r["suite"] != "harness" and not (r["suite"] == "scenarios" and not r.get("nav")):
            kinds[r.get("kind") or "?"] = kinds.get(r.get("kind") or "?", 0) + 1
    L += ["", "## Ce que montrent les tests réussis (classification DOM de la dernière page, hors auto-tests du harnais)", ""]
    blind = {k: n for k, n in kinds.items() if k in ("auth", "error-page", "blank", "login", "truncated") or k.startswith("http-")}
    if blind:
        L.append("**ALARME : des tests réussis se terminent sur %s — l'oracle est aveugle sur ces écrans.**" % ", ".join("%s ×%d" % kv for kv in blind.items()))
    L.append(", ".join("%s ×%d" % (k, n) for k, n in sorted(kinds.items(), key=lambda kv: -kv[1])) or "aucun test réussi")
    groups = {}
    for r in rows:
        if r["status"] == "passed" and r.get("text_hash") and r["suite"] == "screens" and not r.get("bare"):
            groups.setdefault(r["text_hash"], {})[(r.get("url") or r["id"]).split("?")[0]] = r["id"]
    dup = [(h, list(ids.values())) for h, ids in groups.items() if len(ids) >= 3]
    if dup:
        L += ["", "### ALARME : écrans réussis au contenu identique (un même texte pour des URL différentes = oracle aveugle ou écran générique)", ""]
        for h, ids in sorted(dup, key=lambda kv: -len(kv[1]))[:5]:
            L.append("- ×%d %s …" % (len(ids), ", ".join("`%s`" % i for i in ids[:6])))
    skipped = [r for r in rows if r["status"] == "skipped"]
    fails = [r for r in rows if r["status"] not in ("passed", "skipped")]
    causes = js("causes.json")

    def line(r):
        c = (causes.get(r["id"]) or {}).get("causes") or []
        conf = [x for x in c if x.startswith("[confirmed]")]
        # A cause is confirmed when the failing screen's own bean or JSP appears in the log block; otherwise it is
        # only what the server logged at the same moment, in parallel, and saying so avoids a wrong diagnosis.
        cause = ""
        if c:
            cause = (" ⇐ " if conf else " ⇐ piste, non confirmée : ") + (conf[0] if conf else c[0])[12:].strip()[:140]
        return "- `%s` — %s%s" % (r["id"], r.get("reason", "")[:200].replace("\n", " "), cause)

    env_fails = [r for r in fails if not is_target(r)]
    fails = [r for r in fails if is_target(r)]
    front = [r for r in fails if not r.get("bare") and re.search(r"JS errors|console not clean|failed sub-requests|js errors", r.get("reason", ""))]
    robust = [r for r in fails if r.get("bare")]
    functional = [r for r in fails if r not in front and r not in robust]
    L += ["", "## Défauts fonctionnels (%d) — écran ou action avec ses paramètres, scénario, formulaire" % len(functional), ""]
    L += [line(r) for r in sorted(functional, key=lambda r: r["id"])[:60]] or ["Aucun."]
    L += ["", "## Défauts front (%d) — erreurs JavaScript, console, sous-requêtes en échec" % len(front), ""]
    L += [line(r) for r in sorted(front, key=lambda r: r["id"])[:40]] or ["Aucun."]
    L += ["", "## Robustesse (%d) — écran appelé sans ses paramètres : un message Lutece est attendu, pas une erreur interne" % len(robust), ""]
    L += [line(r) for r in sorted(robust, key=lambda r: r["id"])[:60]] or ["Aucun."]
    if env_fails:
        L += ["", "## Environnement (%d rouges hors périmètre : core et autres plugins du site)" % len(env_fails), "",
              "Ils ne concernent pas l'artefact testé ; à rapprocher du banc du core. Les %d premiers :" % min(len(env_fails), 15)]
        L += [line(r) for r in sorted(env_fails, key=lambda r: r["id"])[:15]]
    if skipped:
        L += ["", "## Ignorés (%d) — la donnée qu'ils visaient a été consommée par un autre test" % len(skipped), ""]
        L += ["- `%s` — %s" % (r["id"], r.get("reason", "")[:160]) for r in skipped[:20]]

    noisy = [r for r in rows if r.get("console") or r.get("js_errors") or r.get("bad_requests")]
    L += ["", "## Console navigateur (%d écrans non propres)" % len(noisy), ""]
    counts = {}
    for r in noisy:
        for c in r.get("console", []):
            counts[c["text"][:120]] = counts.get(c["text"][:120], 0) + 1
        for e in r.get("js_errors", []):
            counts["JS: " + e[:120]] = counts.get("JS: " + e[:120], 0) + 1
        for q in r.get("bad_requests", []):
            counts["HTTP %s %s" % (q["status"], q["url"][:100])] = counts.get("HTTP %s %s" % (q["status"], q["url"][:100]), 0) + 1
    for msg, n in sorted(counts.items(), key=lambda kv: -kv[1])[:15]:
        L.append("- ×%d %s" % (n, msg))

    screens = [r for r in rows if r["suite"] == "screens" and r.get("ms")]
    if screens:
        ms = sorted(r["ms"] for r in screens)
        L += ["", "## Temps de navigation (navigateur, %d écrans) : p50 %d ms, p95 %d ms, max %d ms" % (len(ms), statistics.median(ms), ms[int(len(ms) * .95) - 1], ms[-1]), ""]
        over = [r for r in screens if r["ms"] > BUDGET_MS]
        L.append("Au-dessus du budget %d ms : %d écran(s)." % (BUDGET_MS, len(over)))
        for r in sorted(screens, key=lambda r: -r["ms"])[:10]:
            L.append("- %d ms `%s`" % (r["ms"], r.get("url", r["id"])))
    al = perf.get("access_log", {})
    if al.get("slowest"):
        L += ["", "## Temps serveur (access log Liberty, %d requêtes)" % al.get("requests", 0), "", "| Chemin | n | p50 | p95 | max |", "|---|---|---|---|---|"]
        for r in al["slowest"][:12]:
            L.append("| `%s` | %d | %s | %s | %s |" % (r["path"], r["n"], r["p50_ms"], r["p95_ms"], r["max_ms"]))
    se = perf.get("server_errors", {})
    if se.get("unexpected"):
        L += ["", "## Erreurs serveur INATTENDUES (%d) — exception hors liste blanche : un défaut à corriger ou à acquitter dans harness/server-errors-allow.txt" % se.get("unexpected_total", 0), ""]
        for t in se["unexpected"][:15]:
            L.append("- ×%d %s" % (t["n"], t["msg"][:170]))
    if se.get("errors"):
        own = {t["msg"] for t in se.get("unexpected", [])}
        L += ["", "## Erreurs côté serveur (messages.log) : %d lignes, %d distinctes (dont %d inattendues)" % (se["errors"], se["distinct"], se.get("unexpected_total", 0)), "",
              "`artefact` = attribuée à l'artefact sous test. Les autres viennent du core, du thème ou de",
              "l'environnement : elles restent à nommer dans le rapport, hors périmètre, jamais à taire.", ""]
        for t in se["top"][:10]:
            L.append("- ×%d %s%s" % (t["n"], "`artefact` " if t["msg"] in own else "", t["msg"][:150]))
    db = perf.get("db", {})
    if db.get("top"):
        L += ["", "## SQL (performance_schema, top par temps cumulé)", "", "| n | total ms | moy ms | lignes lues | sans index | requête |", "|---|---|---|---|---|---|"]
        for t in db["top"][:10]:
            L.append("| %d | %s | %s | %s | %s | `%s` |" % (t["count"], t["total_ms"], t["avg_ms"], t["rows_examined"], t["no_index"], t["sql"][:110].replace("|", "/")))
        if db.get("full_scans_over_10k_rows"):
            L += ["", "Requêtes sans index lisant > 10 000 lignes : %d (goulots probables)." % len(db["full_scans_over_10k_rows"])]
        nplus1 = per_row(db.get("top", []), sum(len(r.get("nav") or []) for r in rows))
        if nplus1:
            L += ["", "### Requêtes exécutées par ligne (N+1 probable)", "",
                  "Une requête jouée bien plus souvent que le banc n'a ouvert de pages est exécutée dans une boucle,",
                  "une fois par ligne lue. C'est le goulot le plus fréquent et le plus simple à corriger.", "",
                  "| exécutions | par page ouverte | total ms | requête |", "|---|---|---|---|"]
            for t, ratio in nplus1:
                L.append("| %d | ×%.0f | %s | `%s` |" % (t["count"], ratio, t["total_ms"], t["sql"][:90].replace("|", "/")))
    if perf.get("k6"):
        k = perf["k6"]
        d = k.get("http_req_duration", {})
        L += ["", "## Charge k6 : %s requêtes, p95 %.0f ms, max %.0f ms, échecs %.2f %%" % (
            int(k.get("http_reqs", {}).get("count", 0)), d.get("p(95)", 0), d.get("max", 0), 100 * k.get("http_req_failed", {}).get("rate", 0) if k.get("http_req_failed") else 0)]
    if perf.get("jfr"):
        L += ["", "## JFR (méthodes chaudes, extrait)", "", "```", *perf["jfr"].splitlines()[:28], "```"]
    md = perf.get("metrics_delta", {})
    pool = {k: v for k, v in md.items() if "connectionpool" in k.lower()}
    if pool:
        L += ["", "## Pool JDBC (delta pendant les tests)", ""]
        for k, v in list(pool.items())[:8]:
            L.append("- %s = %s" % (k, v))
    L += ["", "Détails et captures : `artifacts/report.html`. JUnit : `artifacts/junit-*.xml`."]
    return "\n".join(L)


NUMERIC = re.compile(r"^[\d.,\s%]+$")


def md_inline(t):
    """Inline markdown of the summary: escaped text, then code spans and bold."""
    t = html.escape(t)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    return re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", t)


def md_html(md):
    """The summary rendered as HTML: headings, tables, lists and paragraphs.

    The summary is the report's first screen; left in a <pre> its tables are unreadable and its hierarchy is
    lost. Only the constructs `summary` emits are handled, on purpose.
    """
    out, lines, i = [], md.splitlines(), 0
    if lines and lines[0].startswith("# "):
        i = 1
    while i < len(lines):
        line = lines[i]
        if line.startswith("|") and i + 1 < len(lines) and set(lines[i + 1].replace("|", "").strip()) <= set("-: "):
            head = [c.strip() for c in line.strip("|").split("|")]
            i += 2
            body = []
            while i < len(lines) and lines[i].startswith("|"):
                body.append([c.strip() for c in lines[i].strip("|").split("|")])
                i += 1
            grid = []
            for r in body:
                cells = r[:len(head)] + [""] * (len(head) - len(r))
                if len(r) > len(head):
                    cells[-1] = " ".join(r[len(head) - 1:])
                grid.append(cells)
            num = [all(NUMERIC.match(row[c]) for row in grid if row[c]) and any(row[c] for row in grid)
                   for c in range(len(head))]
            cls = lambda c: " class=num" if num[c] else ""
            out.append("<div class=scroll><table><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>" % (
                "".join("<th%s>%s</th>" % (cls(c), md_inline(h)) for c, h in enumerate(head)),
                "".join("<tr>%s</tr>" % "".join("<td%s>%s</td>" % (cls(c), md_inline(v))
                                                for c, v in enumerate(row)) for row in grid)))
            continue
        if line.startswith(">"):
            quote = []
            while i < len(lines) and lines[i].startswith(">"):
                quote.append(lines[i].lstrip("> "))
                i += 1
            out.append("<blockquote>%s</blockquote>" % md_inline(" ".join(quote)))
            continue
        m = re.match(r"^(#{1,4})\s+(.*)", line)
        if m:
            n = min(len(m.group(1)) + 1, 5)
            out.append("<h%d>%s</h%d>" % (n, md_inline(m.group(2)), n))
            i += 1
            continue
        if line.startswith("- "):
            items = []
            while i < len(lines) and lines[i].startswith("- "):
                items.append("<li>%s</li>" % md_inline(lines[i][2:]))
                i += 1
            out.append("<ul>%s</ul>" % "".join(items))
            continue
        if not line.strip():
            i += 1
            continue
        para = []
        while i < len(lines) and lines[i].strip() and not lines[i].startswith(("|", "#", "- ")):
            para.append(lines[i])
            i += 1
        out.append("<p>%s</p>" % md_inline(" ".join(para)))
    return "\n".join(out)


def main():
    rows = load_results()
    perf, disc, inv = js("perf.json"), js("discovered.json"), js("inventory.json")
    cov, causes = js("coverage.json"), js("causes.json")
    md = summary(rows, perf, disc, inv)
    (A / "summary.md").write_text(md)
    when = datetime.datetime.now().strftime("%d/%m/%Y %H:%M")
    (A / "report.html").write_text(report_page.render(rows, perf, md, inv, cov, causes, target_matcher(cov, inv), md_html, when))
    (A / "results.json").write_text(json.dumps(rows, ensure_ascii=False, indent=0))
    print("summary.md (%d lignes), report.html (%d Ko), %d résultats" % (md.count("\n"), (A / "report.html").stat().st_size // 1024, len(rows)))


if __name__ == "__main__":
    main()
