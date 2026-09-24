#!/usr/bin/env python3
"""Before / after: the same suites run on the artefact in v7 and, on the same database, in v8.

Reads artifacts/v7/results/*.jsonl and artifacts/v8/results/*.jsonl (written by `run.sh compare`) and puts the
two runs face to face, by FUNCTION rather than by url: a migration to MVC replaces `ModifyMyEntity.jsp?id=1` by
`ManageMyEntities.jsp?view=modifyMyEntity&id=1`, and a reader wants those two on one line with both screenshots,
not one "gone" and one "new". The function of a url is its view (or action) parameter when it has one, else the
JSP name; the Do/Get/Confirm prefixes are dropped (DoCreateMyEntity.jsp is the action createMyEntity,
RemoveMyEntity.jsp is the confirmation confirmRemoveMyEntity). Screens that differ only by their ids are variants of one function: the
report shows one representative per function, with its screenshots, and folds the variants under it.

Writes artifacts/compare.md (the table) and artifacts/compare.html (every function with v7 left, v8 right).
The oracle stays the suites'; this file only pairs and lays out."""
import html
import json
import pathlib
import re
import urllib.parse

E2E = pathlib.Path(__file__).resolve().parents[1]
A = E2E / "artifacts"
NOISE_PARAMS = {"view", "action", "plugin_name", "token", "page_id", "portlet_type_id", "page_index"}


def load(version):
    """The results of one leg, each with the server-side causes causes.py found for it in that leg's own log."""
    rows = []
    d = A / version / "results"
    f = A / version / "causes.json"
    causes = json.loads(f.read_text()) if f.exists() else {}
    for f in sorted(d.glob("*.jsonl")) if d.exists() else []:
        for line in f.read_text().splitlines():
            if line.strip():
                r = json.loads(line)
                r["causes"] = (causes.get(r["id"]) or {}).get("causes") or []
                rows.append(r)
    return rows


def function(u):
    """(directory, function name, ids) of a url, the same for a v7 JSP and the v8 view that replaced it."""
    path, _, q = u.partition("?")
    params = dict(urllib.parse.parse_qsl(q))
    folder, _, base = path.rpartition("/")
    base = re.sub(r"\.jsp$", "", base, flags=re.I)
    name = params.get("view") or params.get("action") or base
    name = re.sub(r"^(do|get|confirm)(?=[A-Z])", "", name)
    ids = tuple(sorted((k, v) for k, v in params.items() if k not in NOISE_PARAMS))
    return folder, name[:1].lower() + name[1:], ids


def key(r):
    """What a test exercises, independent of the pytest id it got in one run: (suite, folder, function, ids)."""
    s = r["suite"]
    if s == "scenarios":
        sid = r.get("scenario") or re.sub(r"^test_scenario\[(?:[^.\]]+\.)?([^\]]+)\]$", r"\1", r["id"])
        return ("scénario", "", sid, ())
    u = r.get("url") or r.get("action") or r.get("final")
    if not u:
        return (s, "", r["id"], ())
    folder, name, ids = function(u)
    # A GET form and the screen it opens are the same function: the two suites are one family for the pairing.
    return ("front" if s == "fo" else "écran", folder, name, ids)


def state(r):
    return {"passed": "ok", "skipped": "skip"}.get(r["status"], "ko")


INTERACTION = ("goto", "wait", "click", "click_if", "dblclick", "drag", "fill", "fill_form", "type", "select", "upload",
               "submit", "submit_novalidate", "confirm", "confirm_if", "login", "login_fo")
"""Steps that drive the parcours without checking anything: a v7 scenario stopped on one never reached its oracle."""


MISSING_PARAM = re.compile(r'required parameter "[^"]+" .*null/missing|was specified, but had null|NumberFormatException: null')
"""A v7 failure caused by a request parameter the page needs and did not get."""


def missing_param(r):
    """The v7 cause of a failed scenario when it is a request parameter the page did not get: the scenario's url is
    then not the one the real navigation sends (a tab link carries a context, an id...), or v7 had that defect."""
    if r.get("suite") != "scenarios":
        return ""
    return next((c for c in r.get("causes") or [] if MISSING_PARAM.search(c)), "")


def blocked(r):
    """True when a failed scenario stopped on a parcours step, before any of its oracles judged the function, or on
    a request parameter the v7 page did not get."""
    if r.get("suite") != "scenarios":
        return False
    if missing_param(r):
        return True
    kind = r.get("failed_step_kind")
    return kind in INTERACTION if kind else "playwright._impl._errors" in (r.get("reason") or "")


def verdict(r7, r8):
    if r7 is None:
        return "nouveau"
    if r8 is None:
        return "disparu"
    s7, s8 = state(r7), state(r8)
    if s7 == "skip" and s8 != "skip":
        return "v8 seulement"
    if s8 == "skip" and s7 != "skip":
        return "v7 seulement"
    if s7 == s8:
        if s7 == "ok" and (r7.get("kind") or "?") != (r8.get("kind") or "?"):
            return "rendu différent"
        return "inchangé"
    if s8 == "ok":
        return "v7 bloqué" if blocked(r7) else "corrigé"
    if s7 == "ok":
        return "régression"
    return "changé"


ORDER = {"régression": 0, "disparu": 1, "changé": 2, "v7 bloqué": 3, "rendu différent": 4, "corrigé": 5, "nouveau": 6, "v8 seulement": 7, "v7 seulement": 8, "inchangé": 9}


def index(rows):
    """One record per key; when two variants collide the failing one wins, a hidden failure is worse than a duplicate."""
    m = {}
    for r in rows:
        if r["suite"] == "harness":
            continue
        k = key(r)
        if k not in m or (state(m[k]) == "ok" and state(r) != "ok"):
            m[k] = r
    return m


def groups(v7, v8):
    """[(function key, [(ids, r7, r8), ...])] — every pair of one function, worst verdict first."""
    m7, m8 = index(v7), index(v8)
    by = {}
    for k in set(m7) | set(m8):
        by.setdefault(k[:3], []).append((k[3], m7.get(k), m8.get(k)))
    out, unjudged = [], 0
    for g, pairs in by.items():
        # The representative is the worst pair seen on both sides; a variant only one crawl sampled (another id)
        # says nothing about the function and is folded, not judged.
        pairs.sort(key=lambda p: (0 if p[1] and p[2] else 1, ORDER[verdict(p[1], p[2])], p[0]))
        # Skipped on both legs: neither version was judged, so the row would say "inchangé" about nothing. Counted,
        # not listed — the reader needs the number, not a table of empty comparisons.
        if all(state(r) == "skip" for _, r7, r8 in pairs for r in (r7, r8) if r):
            unjudged += 1
            continue
        out.append((g, pairs))
    out.sort(key=lambda gp: (ORDER[verdict(gp[1][0][1], gp[1][0][2])], gp[0]))
    return out, unjudged


def title(g, pairs):
    kind, folder, name = g
    if kind == "scénario":
        r = next((r for _, r7, r8 in pairs for r in (r8, r7) if r), None)
        return (r or {}).get("title") or name
    return name


def where(r):
    return (r.get("url") or r.get("action") or r.get("final") or "").rsplit("/", 1)[-1] if r else "—"


def shot(version, r):
    if not r:
        return ""
    s = r.get("screenshot") or ((r.get("screenshots") or [None])[-1])
    return "%s/%s" % (version, s) if s and (A / version / s).exists() else ""


def reason(r):
    return (r.get("reason") or "").replace("\n", " ") if r and state(r) == "ko" else ""


def skip_note(r):
    """Why a leg did not judge the screen, as the bench wrote it: a leg that skipped proves nothing, and the reader
    has to see whether that was declared or just happened."""
    t = (r.get("reason") or "").replace("\n", " ") if r and state(r) == "skip" else ""
    return t.replace("Skipped: ", "", 1).replace("declared exclusion: ", "", 1)


def counts_of(gs):
    c = {}
    for g, pairs in gs:
        v = verdict(pairs[0][1], pairs[0][2])
        c[v] = c.get(v, 0) + 1
    return c


def v7_warning():
    """What run.sh saw of the v7 leg's own limits: a verdict has to be read with that in front of it."""
    f = A / "v7-render-warning.txt"
    return f.read_text().strip() if f.exists() else ""


def md(gs, unjudged=0):
    c = counts_of(gs)
    L = ["# Avant / après — v7 puis v8 sur la même base", "",
         "Une ligne par fonction (écran, formulaire, scénario) ; les écrans qui ne diffèrent que par leurs identifiants sont des variantes de la même fonction.", "",
         "| Verdict | Fonctions |", "|---|---|"] + ["| %s | %d |" % (v, c[v]) for v in sorted(c, key=ORDER.get)]
    if v7_warning():
        L += ["", "> **" + v7_warning() + "**"]
    if unjudged:
        L += ["", "%d fonction(s) ne sont jugées sur aucune des deux jambes (exclusion déclarée, ou aucun écran à ouvrir) : "
              "elles ne disent rien de la migration et ne figurent pas dans le tableau." % unjudged]
    L += ["", "| Verdict | Fonction | Type | v7 | v8 | Variantes | Détail |", "|---|---|---|---|---|---|---|"]
    for g, pairs in gs:
        ids, r7, r8 = pairs[0]
        v = verdict(r7, r8)
        at = ("à l'étape %s %s" % (r7.get("failed_step"), r7.get("failed_step_kind"))) if r7 and r7.get("failed_step_kind") else "sur une étape du parcours"
        detail = ("v7 en erreur faute d'un paramètre de requête (%s) : l'URL du scénario n'est pas celle de la navigation "
                  "réelle, ou v7 avait ce défaut — la fonction n'est pas comparée" % missing_param(r7)[:120]) if v == "v7 bloqué" and missing_param(r7) else ("v7 arrêté %s, avant toute vérification : la fonction n'est pas comparée (écran v7 cassé en amont, ou "
                  "sélecteur propre à v8 à écrire {v7: …, v8: …}) — %s" % (at, reason(r7)[:120])) if v == "v7 bloqué" else ("v8 : " + reason(r8)[:140]) if reason(r8) else ("v7 : " + reason(r7)[:140]) if reason(r7) else (
            "type de page %s → %s" % (r7.get("kind"), r8.get("kind")) if v == "rendu différent" else
            "v7 non jugé : " + skip_note(r7)[:140] if v == "v8 seulement" else
            "v8 non jugé : " + skip_note(r8)[:140] if v == "v7 seulement" else "")
        L.append("| %s | %s | %s | %s | %s | %d | %s |" % (
            v, title(g, pairs).replace("|", "/"), (r8 or r7)["suite"],
            ("%s · %s" % (state(r7), where(r7))) if r7 else "—", ("%s · %s" % (state(r8), where(r8))) if r8 else "—",
            len(pairs), detail.replace("|", "/")))
    return "\n".join(L)


CSS = """
:root{--bg:#f6f7f9;--card:#fff;--line:#e5e7eb;--ink:#111827;--mute:#6b7280;--soft:#f1f2f5}
@media (prefers-color-scheme:dark){:root{--bg:#0f1115;--card:#171a21;--line:#2a2f3a;--ink:#e5e7eb;--mute:#9ca3af;--soft:#1f232c}}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,system-ui,sans-serif}
main{max-width:1280px;margin:0 auto;padding:28px 20px}
h1{font-size:26px;letter-spacing:-.02em;margin:0 0 4px}.sub{color:var(--mute);margin-bottom:22px}
.tiles{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:26px}
.tile{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 14px;min-width:120px;text-decoration:none;color:inherit}
.tile .n{font-size:22px;font-weight:700}.tile .l{font-size:12px;color:var(--mute)}
h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--mute);margin:30px 0 8px}
.pair{background:var(--card);border:1px solid var(--line);border-radius:12px;margin:12px 0;overflow:hidden}
.pair header{display:flex;gap:10px;align-items:center;padding:12px 16px;flex-wrap:wrap}
.pair h3{margin:0;font-size:15px;flex:1 1 auto}
.tag{font-size:12px;padding:2px 9px;border-radius:99px;background:#eef2ff;color:#3730a3;font-weight:600;white-space:nowrap}
.tag.régression,.tag.disparu{background:#fef2f2;color:#b91c1c}.tag.corrigé,.tag.nouveau{background:#ecfdf5;color:#047857}
.tag.changé,.tag.rendu,.tag.bloqué{background:#fffbeb;color:#b45309}.tag.v8,.tag.v7,.tag.inchangé{background:var(--soft);color:var(--mute)}
.kind{font-size:12px;color:var(--mute)}
.side{display:grid;grid-template-columns:1fr 1fr;border-top:1px solid var(--line)}
.side>div{padding:10px 16px;border-right:1px solid var(--line);min-width:0}.side>div:last-child{border-right:0}
.cap{display:flex;justify-content:space-between;gap:8px;font-size:12px;color:var(--mute);margin-bottom:6px}
.cap b{color:var(--ink)}.cap code{font-size:11px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ok{color:#047857}.ko{color:#b91c1c}.skip{color:var(--mute)}
.side img{width:100%;border:1px solid var(--line);border-radius:6px;display:block}
.none{color:var(--mute);font-style:italic;padding:30px 0;text-align:center;border:1px dashed var(--line);border-radius:6px}
.reason{margin-top:8px;color:#b91c1c;font-size:12px;white-space:pre-wrap;word-break:break-word}
.note{margin-top:8px;color:var(--mute);font-size:12px;white-space:pre-wrap;word-break:break-word}
details{border-top:1px solid var(--line)}summary{padding:8px 16px;cursor:pointer;color:var(--mute);font-size:13px}
table{border-collapse:collapse;width:100%;font-size:12px}
th{text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:var(--mute);padding:6px 16px;background:var(--soft)}
td{padding:5px 16px;border-top:1px solid var(--line);color:var(--mute);word-break:break-all}
@media (max-width:800px){.side{grid-template-columns:1fr}.side>div{border-right:0;border-top:1px solid var(--line)}}
"""


def cell(ver, r):
    if not r:
        return '<div><div class=cap><b>%s</b></div><div class=none>n\'existe pas en %s</div></div>' % (ver, ver)
    s = shot(ver, r)
    img = '<a href="%s" target=_blank><img loading=lazy src="%s"></a>' % (s, s) if s else '<div class=none>pas de capture</div>'
    return '<div><div class=cap><b>%s</b> <span class=%s>%s</span> <code title="%s">%s</code> <span>%s</span></div>%s%s</div>' % (
        ver, state(r), state(r), html.escape(where(r)), html.escape(where(r)), html.escape(r.get("kind") or ""), img,
        ('<div class=reason>%s</div>' % html.escape(reason(r)[:600])) if reason(r)
        else ('<div class=note>non jugé : %s</div>' % html.escape(skip_note(r)[:600])) if skip_note(r) else "")


def page(gs, name, unjudged=0):
    c = counts_of(gs)
    H = ["<!doctype html><html lang=fr><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>",
         "<title>Avant / après — %s</title><style>%s</style><body><main>" % (html.escape(name), CSS),
         "<h1>Avant / après — %s</h1><div class=sub>Les mêmes parcours sur l'artefact en v7 puis en v8, sur la même base de données. "
         "Une carte par fonction, v7 à gauche, v8 à droite ; les variantes (autres identifiants) sont repliées dessous."
         "%s%s</div>" % (html.escape(name),
                       " " + html.escape(v7_warning()) if v7_warning() else "",
                       " %d fonction(s) ne sont jugées sur aucune des deux jambes et ne sont pas affichées." % unjudged if unjudged else ""),
         "<div class=tiles>%s</div>" % "".join('<a class=tile href="#%s"><div class=n>%d</div><div class=l>%s</div></a>' % (
             html.escape(v.replace(" ", "-")), c[v], html.escape(v)) for v in sorted(c, key=ORDER.get))]
    current = None
    for g, pairs in gs:
        ids, r7, r8 = pairs[0]
        v = verdict(r7, r8)
        if v != current:
            current = v
            H.append('<h2 id="%s">%s — %d</h2>' % (html.escape(v.replace(" ", "-")), html.escape(v), c[v]))
        H.append('<section class=pair><header><span class="tag %s">%s</span><h3>%s</h3><span class=kind>%s%s</span></header>' % (
            html.escape(v.split()[0]), html.escape(v), html.escape(title(g, pairs)), html.escape((r8 or r7)["suite"]),
            (" · %d variantes" % len(pairs)) if len(pairs) > 1 else ""))
        H.append('<div class=side>%s%s</div>' % (cell("v7", r7), cell("v8", r8)))
        if len(pairs) > 1:
            rows = "".join("<tr><td>%s</td><td>%s</td><td class=%s>%s</td><td class=%s>%s</td></tr>" % (
                html.escape(verdict(a, b)), html.escape(urllib.parse.urlencode(i) or "—"),
                state(a) if a else "", ("%s · %s" % (state(a), html.escape(where(a)))) if a else "—",
                state(b) if b else "", ("%s · %s" % (state(b), html.escape(where(b)))) if b else "—") for i, a, b in pairs)
            H.append("<details><summary>%d variantes</summary><table><tr><th>Verdict</th><th>Identifiants</th><th>v7</th><th>v8</th></tr>%s</table></details>" % (len(pairs), rows))
        H.append("</section>")
    H.append("</main></html>")
    return "\n".join(H)


def main():
    v7, v8 = load("v7"), load("v8")
    if not v7 or not v8:
        print("compare: need both artifacts/v7/results and artifacts/v8/results (run.sh compare writes them)")
        return 2
    gs, unjudged = groups(v7, v8)
    name = pathlib.Path((json.loads((A / "inventory.json").read_text()) if (A / "inventory.json").exists() else {}).get("root", "")).name or "artefact"
    (A / "compare.md").write_text(md(gs, unjudged))
    (A / "compare.html").write_text(page(gs, name, unjudged))
    c = counts_of(gs)
    print("compare: " + ", ".join("%s %d" % (v, c[v]) for v in sorted(c, key=ORDER.get))
          + (", %d non jugée(s) des deux côtés" % unjudged if unjudged else "") + " → artifacts/compare.md, compare.html")
    # Only a regression — green in v7, red in v8 — fails the comparison.
    return 1 if c.get("régression") else 0


if __name__ == "__main__":
    raise SystemExit(main())
