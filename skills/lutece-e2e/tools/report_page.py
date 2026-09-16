"""The HTML report, written for the person who reviews a bench without having run it.

Everything a suite records is technical: a pytest id, a url, a status. This module turns it back into what the
bench meant — a scenario is shown by its title, its right and its steps in plain words; a screen by the feature
and the view it opens, its variants grouped; a form by the action it posts. Failures come first, the technical
material (coverage tables, performance, server errors) stays available under a fold. `report.py` keeps the
loading and the markdown summary; this file only renders."""
import html
import json
import pathlib
import re
import urllib.parse

try:
    import yaml
except ImportError:  # the report must still render where pyyaml is absent: steps are then not listed
    yaml = None

E2E = pathlib.Path(__file__).resolve().parents[1]
A = E2E / "artifacts"

SUITE_LABEL = {"scenarios": "Scénarios", "screens": "Écrans", "fo": "Pages publiques", "forms": "Formulaires", "harness": "Harnais"}
SUITE_ORDER = ("scenarios", "screens", "forms", "fo", "harness")
KIND_FR = {"screen": "page complète", "fragment": "fragment sans menu", "confirmation": "question de confirmation", "error": "message d'erreur",
           "info": "message d'information", "error-page": "page d'erreur", "http-500": "erreur interne", "login": "page de connexion",
           "auth": "authentification demandée", "public-form": "formulaire public", "fo": "page du site", "blank": "page vide",
           "truncated": "page tronquée", "menu": "menu seul", "unknown": "non classée"}


def kind_fr(k):
    return KIND_FR.get(k or "", k or "")


def esc(s):
    return html.escape(str(s if s is not None else ""))


def state(r):
    return {"passed": "ok", "skipped": "skip"}.get(r["status"], "ko")


# ---------------------------------------------------------------------------------------------------------- scenarios

def load_scenarios():
    """The scenario definitions, by id: title, right, description and steps come from the yaml, not from the run."""
    idx = {}
    if yaml is None or not (E2E / "scenarios").exists():
        return idx
    for f in sorted((E2E / "scenarios").glob("*.yaml")):
        if f.name.startswith("coverage-") or f.name.endswith(".example"):
            continue
        try:
            doc = yaml.safe_load(f.read_text()) or {}
        except Exception:  # noqa: BLE001 — a broken file is the suite's problem, not the report's
            continue
        for sc in doc.get("scenarios", []) or []:
            if isinstance(sc, dict) and sc.get("id"):
                sc["_file"] = f.stem
                idx[sc["id"]] = sc
    return idx


def _short_url(u):
    """`jsp/admin/plugins/x/Manage.jsp?view=a&id=1` → `Manage.jsp?view=a&id=1`."""
    u = str(u or "")
    path, _, q = u.partition("?")
    name = path.rsplit("/", 1)[-1] or path
    return name + ("?" + q if q else "")


def _nav_url(u):
    """`http://host/ctx/jsp/admin/X.jsp?view=a` → `jsp/admin/X.jsp?view=a`, whatever the context path."""
    try:
        pu = urllib.parse.urlsplit(str(u or ""))
        path = pu.path.split("/", 2)[-1] if pu.path.count("/") >= 2 else pu.path.lstrip("/")
        return path + ("?" + pu.query if pu.query else "")
    except Exception:  # noqa: BLE001
        return str(u or "")


def _kv(d):
    return ", ".join("%s = %s" % (k, _val(v)) for k, v in (d or {}).items())


def _val(v):
    if isinstance(v, (dict, list)):
        return json.dumps(v, ensure_ascii=False)
    return "« %s »" % v if isinstance(v, str) else str(v)


def step_text(step):
    """One step in plain words: (verb, detail). The vocabulary mirrors tests/test_scenarios.py."""
    if not isinstance(step, dict) or not step:
        return ("?", esc(step))
    key = next((k for k in step if k != "name"), None)
    arg = step.get(key)
    a = arg if isinstance(arg, dict) else {}
    S = lambda v: esc(_val(v) if not isinstance(v, str) else v)  # noqa: E731
    if key == "goto":
        return ("Ouvre", "<code>%s</code>" % esc(_short_url(arg)))
    if key == "login":
        return ("Se connecte", esc(_kv(a)) if a else "avec le compte du banc")
    if key == "click":
        return ("Clique sur", "<code>%s</code>" % esc(arg))
    if key == "click_if":
        return ("Clique, s'il existe, sur", "<code>%s</code>" % esc(arg))
    if key == "fill":
        return ("Saisit", "; ".join("<code>%s</code> ← %s" % (esc(k), S(v)) for k, v in a.items()) or esc(arg))
    if key == "fill_form":
        vals = a.get("values") or {}
        return ("Remplit le formulaire", "<code>%s</code> : %s" % (esc(a.get("form", "")), "; ".join("%s ← %s" % (esc(k), S(v)) for k, v in vals.items())))
    if key == "upload":
        return ("Dépose le fichier", "<code>%s</code> dans <code>%s</code>" % (esc(a.get("file")), esc(a.get("selector"))))
    if key in ("submit", "submit_novalidate"):
        return ("Soumet", "<code>%s</code>%s" % (esc(arg), " (sans validation navigateur)" if key.endswith("novalidate") else ""))
    if key == "confirm":
        return ("Confirme", "la question Lutece affichée")
    if key == "confirm_if":
        return ("Confirme, si une question est affichée", "")
    if key == "wait":
        return ("Attend l'apparition de", "<code>%s</code>" % esc(arg))
    if key == "shot":
        return ("Capture l'écran", "<code>%s</code>" % esc(arg))
    if key == "set":
        return ("Pose la variable", esc(_kv(a)))
    if key == "dom_set":
        return ("Lit dans la page", "<code>%s</code> (%s) → <code>{{%s}}</code>" % (esc(a.get("selector")), esc(a.get("attr", "text")), esc(a.get("var"))))
    if key == "sql_set":
        return ("Lit en base", "<code>%s</code> → <code>{{%s}}</code>" % (esc(a.get("query")), esc(a.get("var"))))
    if key == "sql_exec":
        return ("Exécute en base", "<code>%s</code>" % esc(arg))
    if key == "sql":
        exp = [("vaut", "expect"), ("ne vaut pas", "not_expect"), ("vaut la variable", "expect_var"), ("contient", "contains"), ("ne contient pas", "not_contains")]
        checks = ["%s %s" % (lbl, S(a[k])) for lbl, k in exp if k in a]
        return ("Vérifie en base", "<code>%s</code> %s" % (esc(a.get("query")), " et ".join(checks)))
    if key == "http":
        return ("Appelle", "<code>%s %s</code>%s" % (esc((a.get("method") or "GET").upper()), esc(_short_url(a.get("url"))),
                                                     " et attend %s" % esc(a["status"]) if "status" in a else ""))
    if key == "mail":
        return ("Attend un courriel", "pour <code>%s</code>%s" % (esc(a.get("to")), " dont l'objet contient %s" % S(a["subject"]) if a.get("subject") else ""))
    if key == "fake_log":
        return ("Vérifie chez le système simulé", esc(_kv(a)))
    if key == "expect_ok":
        return ("La page répond", "sans erreur ni message d'erreur")
    if key == "expect_kind":
        return ("La page est", "de type <code>%s</code>" % esc(arg))
    if key == "expect_url":
        return ("L'adresse contient", "<code>%s</code>" % esc(arg))
    if key == "expect_message":
        return ("Un message Lutece s'affiche", "de type <code>%s</code>" % esc(arg))
    if key == "expect_text":
        return ("Le texte est présent", S(arg))
    if key == "expect_not_text":
        return ("Le texte est absent", S(arg))
    if key == "expect_html":
        return ("Le HTML contient", "<code>%s</code>" % esc(arg))
    if key == "expect_dom":
        parts = []
        if "count" in a:
            parts.append("exactement %s élément(s)" % esc(a["count"]))
        if "min" in a:
            parts.append("au moins %s élément(s)" % esc(a["min"]))
        if "attr" in a:
            parts.append("attribut <code>%s</code>%s" % (esc(a["attr"]), " = %s" % S(a["equals"]) if "equals" in a else ""))
        if "contains" in a:
            parts.append("contenant %s" % S(a["contains"]))
        if "not_contains" in a:
            parts.append("ne contenant pas %s" % S(a["not_contains"]))
        return ("Dans la page", "<code>%s</code> : %s" % (esc(a.get("selector")), ", ".join(parts) or "présent"))
    if key == "download":
        return ("Télécharge", "<code>%s</code>" % esc(a.get("selector") or arg))
    return (esc(key), esc(json.dumps(arg, ensure_ascii=False)) if not isinstance(arg, str) else esc(arg))


def scenario_card(r, sc, causes):
    st = state(r)
    title = r.get("title") or (sc or {}).get("title") or r.get("scenario") or r["id"]
    req = r.get("requirement") or (sc or {}).get("req") or ""
    anon = bool((sc or {}).get("anonymous"))
    desc = r.get("description") or (sc or {}).get("description") or ""
    failed = r.get("failed_step")
    pills = []
    if anon:
        pills.append('<span class=pill>visiteur anonyme</span>')
    elif req:
        pills.append('<span class=pill title="Droit d\'administration exigé">droit <code>%s</code></span>' % esc(req))
    if r.get("duration_ms"):
        pills.append('<span class=pill>%.1f s</span>' % (r["duration_ms"] / 1000))
    if (sc or {}).get("_file"):
        pills.append('<span class="pill dim">%s.yaml</span>' % esc(sc["_file"]))
    steps_html = ""
    steps = (sc or {}).get("steps") or []
    if steps:
        items = []
        for i, step in enumerate(steps):
            verb, detail = step_text(step)
            cls = " class=ko" if failed is not None and i == failed else (" class=notrun" if failed is not None and i > failed else "")
            items.append("<li%s><span class=verb>%s</span> %s</li>" % (cls, verb, detail))
        steps_html = '<ol class=steps>%s</ol>' % "".join(items)
    reason = ""
    if st == "ko":
        c = (causes.get(r["id"]) or {}).get("causes") or []
        conf = [x for x in c if x.startswith("[confirmed]")]
        cause = ""
        if c:
            cause = "<div class=cause>%s%s</div>" % ("Cause côté serveur : " if conf else "Piste côté serveur, non confirmée : ",
                                                     esc((conf[0] if conf else c[0])[12:].strip()[:300]))
        where = " à l'étape %d" % (failed + 1) if failed is not None else ""
        reason = '<div class=fail><strong>Échec%s</strong> — %s%s</div>' % (where, esc((r.get("reason") or "")[:500]), cause)
    elif st == "skip":
        reason = '<div class="fail skip">Ignoré — %s</div>' % esc((r.get("reason") or "")[:300])
    shots = [s for s in ([r.get("screenshot")] + (r.get("screenshots") or [])) if s and s.endswith((".jpg", ".png")) and (A / s).exists()]
    gallery = "".join('<a class=thumb href="%s" target=_blank><img loading=lazy src="%s" alt=""></a>' % (esc(s), esc(s)) for s in shots)
    trail = ""
    nav = r.get("nav") or []
    if nav:
        rows = "".join("<li><span class=st>%s</span> <code>%s</code>%s</li>" % (
            esc(n.get("status")), esc(_nav_url(n.get("url", ""))),
            " <span class=dim>%s</span>" % esc(n["mvc"]) if n.get("mvc") else "") for n in nav[:40])
        trail = "<details><summary>Parcours dans l'application (%d pages)</summary><ul class=trail>%s</ul></details>" % (len(nav), rows)
    noise = {k: v for k, v in (("console", r.get("console")), ("erreurs JS", r.get("js_errors")), ("requêtes en échec", r.get("bad_requests"))) if v}
    noise_html = "<details><summary>Console navigateur</summary><pre>%s</pre></details>" % esc(json.dumps(noise, ensure_ascii=False, indent=1)) if noise else ""
    return ('<article class="scn %s" id="%s"><header><span class="dot %s"></span><div class=hd><h4>%s</h4><div class=pills>%s</div></div></header>'
            '%s%s%s%s%s%s<div class=rawid>%s</div></article>') % (
        st, esc(anchor(r)), st, esc(title), "".join(pills),
        "<p class=desc>%s</p>" % esc(desc) if desc else "",
        reason, steps_html, '<div class=gallery>%s</div>' % gallery if gallery else "", trail, noise_html, esc(r["id"]))


# ------------------------------------------------------------------------------------------------------------ screens

def anchor(r):
    return "t-" + re.sub(r"[^A-Za-z0-9_-]+", "-", r["id"])[:120]


def inv_index(inv):
    """Inventory screens by (path, view) so a url can be named by its bean, its view and its right."""
    idx = {}
    for s in inv.get("screens", []) or []:
        path, _, q = (s.get("url") or "").partition("?")
        view = dict(urllib.parse.parse_qsl(q)).get("view", "")
        idx.setdefault((path, view), s)
        if view:
            idx.setdefault((path, ""), s)
    feats = {(f.get("url") or "").split("?")[0]: f for f in inv.get("features", []) or [] if f.get("url")}
    return idx, feats


def screen_group_key(r):
    u = r.get("url") or r.get("final") or r["id"]
    path, _, q = u.partition("?")
    params = dict(urllib.parse.parse_qsl(q))
    return path, params.get("view", ""), params


def screen_title(path, view, inv_idx, feats):
    s = inv_idx.get((path, view)) or inv_idx.get((path, ""))
    jsp = path.rsplit("/", 1)[-1].replace(".jsp", "") or path
    if s and s.get("bean") and s.get("method") and view:
        title = "%s · vue %s" % (jsp, view)
        meta = "%s.%s" % (s["bean"], s["method"])
    elif view:
        title, meta = "%s · vue %s" % (jsp, view), ""
    else:
        title, meta = jsp, (s or {}).get("bean") or ""
    right = (s or {}).get("right") or (feats.get(path) or {}).get("right") or ""
    return title, meta, right


def screens_section(rows, inv, title, anchor_id, note="", collapsed=False, empty=""):
    """Screens grouped by (path, view): one card per family, its variants as chips, the failed variant's shot first.
    A skipped result that never opened a url (pytest's empty parameter set, a core screen out of scope) is a line,
    not a card."""
    if not rows:
        return ""
    skipped = [r for r in rows if state(r) == "skip" and not r.get("url") and not r.get("screenshot")]
    rows = [r for r in rows if r not in skipped]
    placeholder = [r for r in skipped if "NOTSET" in r["id"]]
    skipped = [r for r in skipped if r not in placeholder]
    if not rows and not skipped:
        return ('<section id="%s"><h2>%s <span class=count>aucun</span></h2><p class=note>%s</p></section>' % (anchor_id, esc(title), esc(empty))) if empty else ""
    inv_idx, feats = inv_index(inv)
    groups = {}
    for r in rows:
        path, view, params = screen_group_key(r)
        g = groups.setdefault((path, view), {"rows": [], "params": []})
        g["rows"].append(r)
        g["params"].append({k: v for k, v in params.items() if k != "view"})
    cards = []
    for (path, view), g in sorted(groups.items(), key=lambda kv: (all(x["status"] == "passed" for x in kv[1]["rows"]), kv[0])):
        rs = g["rows"]
        ko = [x for x in rs if state(x) == "ko"]
        sk = [x for x in rs if state(x) == "skip"]
        st = "ko" if ko else ("skip" if len(sk) == len(rs) else "ok")
        ttl, meta, right = screen_title(path, view, inv_idx, feats)
        rep = (ko or [x for x in rs if x.get("screenshot")] or rs)[0]
        shot = rep.get("screenshot") if rep.get("screenshot") and (A / rep["screenshot"]).exists() else ""
        kinds = sorted({kind_fr(x.get("kind")) for x in rs if x.get("kind") and x.get("kind") != "?"})
        chips = []
        for x, p in sorted(zip(rs, g["params"]), key=lambda t: (state(t[0]) == "ok", t[0]["id"])):
            lbl = " ".join("%s=%s" % (k, v) for k, v in p.items()) or ("sans paramètre" if len(rs) > 1 else "")
            ms = x.get("ms") or x.get("duration_ms")
            parts = [esc(lbl)] if lbl else []
            if ms and state(x) == "ok":
                parts.append("%d ms" % ms)
            chips.append('<span class="chip %s" title="%s">%s</span>' % (state(x), esc(x["id"]), " · ".join(parts) or "ouvert"))
        fails = "".join('<div class=fail><strong>%s</strong> — %s</div>' % (esc(" ".join("%s=%s" % kv for kv in p.items()) or "appel"), esc((x.get("reason") or "")[:400]))
                        for x, p in zip(rs, g["params"]) if state(x) == "ko")
        renders = sorted({f for x in rs for f in (x.get("render_own") or x.get("render") or [])})
        render_html = '<div class=fail><strong>Rendu</strong> — %s</div>' % esc("; ".join(renders)[:300]) if renders else ""
        noise = [c.get("text", "")[:140] for x in rs for c in (x.get("console") or [])] + ["JS : " + e[:140] for x in rs for e in (x.get("js_errors") or [])] + \
                ["HTTP %s %s" % (q.get("status"), q.get("url", "")[:100]) for x in rs for q in (x.get("bad_requests") or [])]
        noise_html = "<details><summary>Console navigateur (%d)</summary><pre>%s</pre></details>" % (len(noise), esc("\n".join(sorted(set(noise))[:30]))) if noise else ""
        cards.append(
            '<article class="scr %s"><header><span class="dot %s"></span><div class=hd><h4>%s</h4><div class=pills>%s%s%s%s</div></div></header>'
            '%s%s<div class=chips>%s</div>%s%s<div class=rawid>%s</div></article>' % (
                st, st, esc(ttl),
                '<span class="pill dim mono">%s</span>' % esc(meta) if meta else "",
                '<span class=pill>droit <code>%s</code></span>' % esc(right) if right else "",
                '<span class=pill>%s</span>' % esc(", ".join(kinds)) if kinds else "",
                '<span class=pill>%d variante%s</span>' % (len(rs), "s" if len(rs) > 1 else "") if len(rs) > 1 else "",
                fails + render_html,
                '<a class="shot" href="%s" target=_blank><img loading=lazy src="%s" alt=""></a>' % (esc(shot), esc(shot)) if shot else "",
                "".join(chips), noise_html, "", esc(path)))
    ko = sum(1 for r in rows if state(r) == "ko")
    skipped_html = ""
    if skipped:
        skipped_html = '<details class=skipped><summary>Non ouverts (%d)</summary><ul>%s</ul></details>' % (len(skipped), "".join(
            "<li><code>%s</code> — %s</li>" % (esc(re.sub(r"^test_\w+\[(.*)\]$", r"\1", r["id"])), esc((r.get("reason") or "").replace("Skipped: ", "")[:200])) for r in skipped))
    body = "%s<div class=grid>%s</div>%s" % ("<p class=note>%s</p>" % note if note else "", "".join(cards), skipped_html)
    if rows:
        count = '%d écran%s, %d famille%s, %d en échec' % (len(rows), "s" if len(rows) > 1 else "", len(groups), "s" if len(groups) > 1 else "", ko)
    else:
        count = '%d non ouvert%s' % (len(skipped), "s" if len(skipped) > 1 else "")
    head = '<h2>%s <span class=count><span class="dot %s"></span>%s</span></h2>' % (esc(title), "ko" if ko else ("skip" if not rows else "ok"), count)
    if collapsed:
        return '<section id="%s" data-cards><details class=fold><summary>%s</summary>%s</details></section>' % (anchor_id, head, body)
    return '<section id="%s" data-cards>%s%s</section>' % (anchor_id, head, body)


# -------------------------------------------------------------------------------------------------------------- forms

def forms_section(rows):
    if not rows:
        return ""
    cards = []
    for r in sorted(rows, key=lambda x: (state(x) == "ok", x["id"])):
        st = state(r)
        action = dict(urllib.parse.parse_qsl((r.get("action") or "").partition("?")[2])).get("action", "") or _short_url(r.get("action"))
        screen = r.get("screen") or ""
        spath, _, sq = screen.partition("?")
        sview = dict(urllib.parse.parse_qsl(sq)).get("view", "")
        filled = r.get("filled") or []
        outcome = []
        if r.get("message"):
            outcome.append("message Lutece : %s" % esc(str(r["message"])[:160]))
        if r.get("final"):
            outcome.append("arrive sur <code>%s</code>" % esc(_short_url(r["final"])))
        if r.get("statuses"):
            outcome.append("HTTP %s" % esc(" → ".join(str(s) for s in r["statuses"])))
        shot = r.get("screenshot") if r.get("screenshot") and (A / r["screenshot"]).exists() else ""
        cards.append(
            '<article class="scr %s"><header><span class="dot %s"></span><div class=hd><h4>Action <code>%s</code></h4><div class=pills>'
            '<span class=pill>depuis <code>%s</code>%s</span>%s%s</div></div></header>%s%s%s%s<div class=rawid>%s</div></article>' % (
                st, st, esc(action), esc(spath.rsplit("/", 1)[-1]), " · vue %s" % esc(sview) if sview else "",
                '<span class=pill>%d champ%s rempli%s</span>' % (len(filled), "s" if len(filled) > 1 else "", "s" if len(filled) > 1 else "") if filled else '<span class="pill dim">sans saisie</span>',
                '<span class=pill>%s</span>' % esc(kind_fr(r.get("screen_kind"))) if r.get("screen_kind") else "",
                '<div class=fail><strong>Échec</strong> — %s</div>' % esc((r.get("reason") or "")[:400]) if st == "ko" else ("<div class='fail skip'>Ignoré — %s</div>" % esc((r.get("reason") or "")[:200]) if st == "skip" else ""),
                "<p class=desc>%s</p>" % " ; ".join(outcome) if outcome else "",
                '<a class="shot" href="%s" target=_blank><img loading=lazy src="%s" alt=""></a>' % (esc(shot), esc(shot)) if shot else "",
                "<details><summary>Champs</summary><pre>%s</pre></details>" % esc(json.dumps(filled, ensure_ascii=False, indent=1)) if filled else "",
                esc(r["id"])))
    ko = sum(1 for r in rows if state(r) == "ko")
    return ('<section id=forms data-cards><h2>Formulaires soumis <span class=count><span class="dot %s"></span>%d, %d en échec</span></h2>'
            '<p class=note>Chaque formulaire trouvé sur les écrans est rempli avec des valeurs de test et soumis. L\'oracle est la réponse de l\'application : un message Lutece ou un écran attendu, jamais une erreur interne.</p>'
            '<div class=grid>%s</div></section>') % ("ko" if ko else "ok", len(rows), ko, "".join(cards))


# ------------------------------------------------------------------------------------------------------------- header

def review_state():
    rv, todo = A / "review.md", A / "review-todo.md"
    if not todo.exists():
        return None
    n = len(re.findall(r"^\| G\d{3} ", todo.read_text(), re.M))
    done = len(set(re.findall(r"\bG\d{3}\b", rv.read_text()))) if rv.exists() else 0
    return n, done


def hero(name, rows, cov, inv, when):
    by = {}
    for r in rows:
        by.setdefault(r["suite"], []).append(r)
    ko = sum(1 for r in rows if state(r) == "ko")
    tiles = []
    for s in SUITE_ORDER:
        rs = by.get(s)
        if not rs:
            continue
        k = sum(1 for r in rs if state(r) == "ko")
        sk = sum(1 for r in rs if state(r) == "skip")
        tiles.append('<a class="tile %s" href="#%s"><span class=n>%d</span><span class=l>%s</span><span class=s>%s</span></a>' % (
            "ko" if k else "ok", {"scenarios": "scenarios", "screens": "screens", "forms": "forms", "fo": "fo", "harness": "tech"}[s],
            len(rs), esc(SUITE_LABEL[s]), ("%d en échec" % k) if k else ("%d ignoré%s" % (sk, "s" if sk > 1 else "") if sk else "tout est vert")))
    rv = review_state()
    review = ""
    if rv:
        n, done = rv
        ok = n and done >= n
        review = '<span class="pill %s"><span class="dot %s"></span>revue visuelle %s</span>' % ("" if ok else "warn", "ok" if ok else "ko", "%d/%d familles jugées" % (done, n))
    coverage = ""
    st = (cov.get("stats_target") or cov.get("stats")) if cov else None
    if st:
        sc, ac = st.get("screens", {}), st.get("actions", {})
        coverage = '<span class=pill title="Éléments de l\'inventaire atteints par un scénario vert">couverture : %d/%d écrans, %d/%d actions prouvés</span>' % (
            sc.get("n_proven", 0), sc.get("total", 0), ac.get("n_proven", 0), ac.get("total", 0))
    verdict = ('<span class="verdict ok">Tout est vert</span>' if not ko else '<span class="verdict ko">%d échec%s</span>' % (ko, "s" if ko > 1 else ""))
    return ('<section class=hero><div class=hbar><div><div class=kicker>Rapport de banc e2e</div><h1>%s</h1><div class=when>%s · %d tests</div></div>%s</div>'
            '<div class=tiles>%s</div><div class=pills>%s%s</div></section>') % (esc(name), esc(when), len(rows), verdict, "".join(tiles), review, coverage)


# ------------------------------------------------------------------------------------------------------------ defects

def defects_section(rows, is_target, causes):
    fails = [r for r in rows if state(r) == "ko"]
    if not fails:
        return ""
    env = [r for r in fails if not is_target(r)]
    own = [r for r in fails if is_target(r)]

    def li(r):
        c = (causes.get(r["id"]) or {}).get("causes") or []
        conf = [x for x in c if x.startswith("[confirmed]")]
        cause = ""
        if c:
            cause = " <span class=dim>⇐ %s%s</span>" % ("" if conf else "piste : ", esc((conf[0] if conf else c[0])[12:].strip()[:160]))
        label = r.get("title") or (r.get("url") or r.get("screen") or r["id"])
        return '<li><a href="#%s"><span class="dot ko"></span>%s</a> <span class=dim>%s</span> — %s%s</li>' % (
            esc(anchor(r)), esc(label), esc(SUITE_LABEL.get(r["suite"], r["suite"])), esc((r.get("reason") or "")[:220].replace("\n", " ")), cause)
    H = ['<section id=defects><h2>À corriger <span class=count><span class="dot ko"></span>%d dans le périmètre%s</span></h2>' % (
        len(own), ", %d hors périmètre" % len(env) if env else "")]
    if own:
        H.append("<ul class=defects>%s</ul>" % "".join(li(r) for r in sorted(own, key=lambda r: (r["suite"] != "scenarios", r["id"]))))
    if env:
        H.append("<details><summary>Hors périmètre — core et autres plugins du site (%d)</summary><ul class=defects>%s</ul></details>" % (len(env), "".join(li(r) for r in sorted(env, key=lambda r: r["id"])[:30])))
    H.append("</section>")
    return "".join(H)


# --------------------------------------------------------------------------------------------------------------- page

CSS = """
:root{--bg:#f6f7f9;--surface:#fff;--surface2:#f1f2f5;--line:#e5e7eb;--line2:#d1d5db;--fg:#111827;--fg2:#4b5563;--fg3:#9ca3af;
--accent:#4f46e5;--ok:#16a34a;--okbg:#ecfdf5;--ko:#dc2626;--kobg:#fef2f2;--warn:#d97706;--warnbg:#fffbeb;--r:12px;--sh:0 1px 2px rgba(16,24,40,.06)}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#0b0f17;--surface:#111827;--surface2:#1f2937;--line:#1f2937;--line2:#374151;--fg:#f3f4f6;--fg2:#c4c9d4;--fg3:#6b7280;
--okbg:rgba(22,163,74,.14);--kobg:rgba(220,38,38,.16);--warnbg:rgba(217,119,6,.16);--sh:none}}
:root[data-theme=dark]{--bg:#0b0f17;--surface:#111827;--surface2:#1f2937;--line:#1f2937;--line2:#374151;--fg:#f3f4f6;--fg2:#c4c9d4;--fg3:#6b7280;
--okbg:rgba(22,163,74,.14);--kobg:rgba(220,38,38,.16);--warnbg:rgba(217,119,6,.16);--sh:none}
*{box-sizing:border-box}[hidden]{display:none!important}
html{color-scheme:light dark}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.55 -apple-system,BlinkMacSystemFont,'Segoe UI',Inter,Roboto,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
a{color:inherit}
code,.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px}
code{background:var(--surface2);border-radius:5px;padding:1px 5px;color:var(--fg)}
main{max-width:1180px;margin:0 auto;padding:0 28px 60px}
.hero{padding:34px 0 18px}
.hbar{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;flex-wrap:wrap}
.kicker{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--fg3);font-weight:600}
h1{font-size:30px;letter-spacing:-.02em;margin:4px 0 2px;font-weight:700}
.when{color:var(--fg2);font-size:13px}
.verdict{font-weight:700;font-size:15px;padding:8px 16px;border-radius:99px}
.verdict.ok{background:var(--okbg);color:var(--ok)}.verdict.ko{background:var(--kobg);color:var(--ko)}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:22px 0 14px}
.tile{display:flex;flex-direction:column;gap:2px;background:var(--surface);border:1px solid var(--line);border-radius:var(--r);padding:14px 16px;text-decoration:none;box-shadow:var(--sh);border-top:3px solid var(--ok)}
.tile.ko{border-top-color:var(--ko)}
.tile .n{font-size:26px;font-weight:700;letter-spacing:-.02em;line-height:1.1}
.tile .l{font-weight:600;font-size:13px}.tile .s{color:var(--fg3);font-size:12px}
.pills{display:flex;gap:6px;flex-wrap:wrap;align-items:center}
.pill{display:inline-flex;align-items:center;gap:6px;border:1px solid var(--line);background:var(--surface);border-radius:99px;padding:2px 10px;font-size:12px;color:var(--fg2);white-space:nowrap}
.pill{white-space:normal;max-width:100%;overflow-wrap:anywhere}.pill code{overflow-wrap:anywhere}
.pill.dim{color:var(--fg3)}
details.fold{border:0}details.fold>summary{padding:0;margin:0 0 14px}details.fold>summary::before{content:''}
details.fold>summary h2{display:inline-flex;cursor:pointer}details.fold>summary h2::before{content:'▸';color:var(--fg3);margin-right:6px;font-size:14px}
details.fold[open]>summary h2::before{content:'▾'}
details.skipped{border:0;margin-top:10px}details.skipped ul{margin:4px 0 0;padding-left:34px;color:var(--fg2);font-size:12.5px}details.skipped li{margin:2px 0}.pill.warn{background:var(--warnbg);border-color:transparent;color:var(--warn)}
.dot{width:8px;height:8px;border-radius:99px;background:var(--fg3);flex:none;display:inline-block}
.dot.ok{background:var(--ok)}.dot.ko{background:var(--ko)}.dot.skip{background:var(--fg3)}
.topnav{position:sticky;top:0;z-index:9;background:color-mix(in srgb,var(--bg) 88%,transparent);backdrop-filter:blur(10px);border-bottom:1px solid var(--line);margin:0 -28px;padding:8px 28px;display:flex;gap:4px;flex-wrap:wrap;align-items:center}
.topnav a{color:var(--fg2);text-decoration:none;font-size:13px;padding:6px 11px;border-radius:8px;font-weight:500}
.topnav a:hover{background:var(--surface2);color:var(--fg)}
.topnav .sp{flex:1}
.topnav button{font:inherit;font-size:12.5px;color:var(--fg2);background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:5px 12px;cursor:pointer}
.topnav button[aria-pressed=true]{background:var(--fg);border-color:var(--fg);color:var(--bg)}
.topnav input{font:inherit;font-size:13px;border:1px solid var(--line);border-radius:8px;padding:5px 10px;background:var(--surface);color:var(--fg);width:220px}
section{margin:34px 0 0}
h2{font-size:18px;letter-spacing:-.01em;margin:0 0 14px;display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}
.count{font-size:12.5px;font-weight:500;color:var(--fg2);display:inline-flex;align-items:center;gap:6px}
.note{color:var(--fg2);margin:-6px 0 14px;font-size:13px;max-width:900px}
article{background:var(--surface);border:1px solid var(--line);border-radius:var(--r);box-shadow:var(--sh);overflow:hidden;content-visibility:auto;contain-intrinsic-size:220px}
article.ko{border-color:color-mix(in srgb,var(--ko) 45%,var(--line))}
article header{display:flex;gap:12px;align-items:flex-start;padding:14px 16px 10px}
article header .dot{margin-top:7px;width:9px;height:9px}
.hd{flex:1;min-width:0}
h4{margin:0 0 6px;font-size:15px;font-weight:600;letter-spacing:-.01em;line-height:1.35}
.scr h4{font-size:14px}
.desc{margin:0 16px 10px;color:var(--fg2)}
.fail{margin:0 16px 10px;padding:10px 12px;border-radius:8px;background:var(--kobg);color:var(--ko);font-size:13px;line-height:1.45}
.fail.skip{background:var(--surface2);color:var(--fg2)}
.fail strong{font-weight:600}
.cause{margin-top:6px;color:var(--fg2);font-size:12.5px}
.scenarios{display:flex;flex-direction:column;gap:12px}
ol.steps{margin:0 16px 12px;padding:0 0 0 30px;counter-reset:s}
ol.steps li{margin:3px 0;color:var(--fg2);position:relative;padding-left:2px}
ol.steps li::marker{color:var(--fg3);font-variant-numeric:tabular-nums;font-size:12px}
ol.steps .verb{color:var(--fg);font-weight:600}
ol.steps li.ko{color:var(--ko);background:var(--kobg);border-radius:6px;padding:3px 8px;margin-left:-8px}
ol.steps li.ko .verb{color:var(--ko)}
ol.steps li.notrun{opacity:.45}
.gallery{display:flex;gap:8px;flex-wrap:wrap;padding:0 16px 12px}
.thumb{display:block;width:220px;aspect-ratio:16/10;border:1px solid var(--line);border-radius:8px;overflow:hidden;background:var(--surface2)}
.thumb img,.shot img{width:100%;height:100%;object-fit:cover;object-position:top;display:block}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:12px}
.shot{display:block;aspect-ratio:16/9;background:var(--surface2);border-top:1px solid var(--line);border-bottom:1px solid var(--line);overflow:hidden}
.chips{display:flex;gap:6px;flex-wrap:wrap;padding:10px 16px}
.chip{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;padding:2px 8px;border-radius:6px;background:var(--surface2);color:var(--fg2);border-left:3px solid var(--ok)}
.chip.ko{border-left-color:var(--ko);background:var(--kobg);color:var(--ko)}.chip.skip{border-left-color:var(--fg3);opacity:.7}
details{border-top:1px solid var(--line)}
summary{cursor:pointer;padding:8px 16px;font-size:12.5px;color:var(--fg2);list-style:none}
summary::-webkit-details-marker{display:none}
summary::before{content:'▸ ';color:var(--fg3)}details[open] summary::before{content:'▾ '}
details pre{margin:0;padding:0 16px 12px;font-size:11.5px;color:var(--fg2);white-space:pre-wrap;word-break:break-word}
ul.trail{margin:0;padding:0 16px 12px 16px;list-style:none;font-size:12px;color:var(--fg2)}
ul.trail li{padding:2px 0}
ul.trail .st{display:inline-block;min-width:30px;color:var(--fg3);font-variant-numeric:tabular-nums}
.dim{color:var(--fg3)}
.rawid{padding:6px 16px 10px;font-family:ui-monospace,Menlo,monospace;font-size:10.5px;color:var(--fg3);word-break:break-all}
ul.defects{margin:0;padding:0;list-style:none}
ul.defects li{padding:9px 12px;border:1px solid var(--line);border-radius:10px;background:var(--surface);margin:6px 0;font-size:13px}
ul.defects a{text-decoration:none;font-weight:600;display:inline-flex;gap:8px;align-items:center}
.tech{background:var(--surface);border:1px solid var(--line);border-radius:var(--r);padding:0}
.tech>summary{padding:14px 18px;font-size:14px;font-weight:600;color:var(--fg)}
.prose{padding:6px 22px 22px}
.prose h2{font-size:15px;margin-top:22px;display:block}.prose h3{font-size:13.5px;margin:18px 0 6px}.prose h4{font-size:13px;color:var(--fg2)}
.prose p,.prose li{color:var(--fg2)}.prose ul{padding-left:18px}
.scroll{overflow-x:auto;margin:10px 0;border:1px solid var(--line);border-radius:8px}
table{border-collapse:collapse;width:100%;font-size:12.5px}
th{text-align:left;font-weight:600;color:var(--fg2);font-size:11px;letter-spacing:.04em;text-transform:uppercase;padding:8px 12px;background:var(--surface2);border-bottom:1px solid var(--line)}
td{padding:7px 12px;border-bottom:1px solid var(--line);color:var(--fg2);vertical-align:top}
th.num,td.num{text-align:right;font-variant-numeric:tabular-nums}
tbody tr:last-child td{border-bottom:0}
blockquote{margin:10px 0;padding:10px 14px;border-left:3px solid var(--accent);background:var(--surface2);border-radius:0 8px 8px 0;color:var(--fg2)}
pre.block{background:var(--surface2);border-radius:8px;padding:12px 14px;overflow:auto;font-size:12px;color:var(--fg2);max-height:420px}
@media (max-width:700px){main{padding:0 16px 40px}.topnav{margin:0 -16px;padding:8px 16px}.grid{grid-template-columns:1fr}.thumb{width:100%}h1{font-size:24px}}
"""

JS = """
const q=document.getElementById('q'), cards=[...document.querySelectorAll('article')];
let onlyKo=false;
function apply(){
  const t=(q.value||'').toLowerCase();
  cards.forEach(c=>{const hit=!t||c.textContent.toLowerCase().includes(t);c.hidden=(onlyKo&&!c.classList.contains('ko'))||!hit;});
  document.querySelectorAll('section[data-cards]').forEach(s=>{s.hidden=[...s.querySelectorAll('article')].every(a=>a.hidden);});
}
q&&q.addEventListener('input',apply);
document.querySelectorAll('button[data-filter]').forEach(b=>b.addEventListener('click',()=>{
  onlyKo=b.dataset.filter==='ko';document.querySelectorAll('button[data-filter]').forEach(x=>x.setAttribute('aria-pressed',x===b));apply();}));
"""


def surface(r):
    if r["suite"] == "fo":
        return "fo"
    if r["suite"] == "screens":
        return "bo"
    visited = r.get("visited") or []
    return "fo" if visited and all(p.startswith("jsp/site/") for p in visited) else "bo"


def render(rows, perf, md, inv, cov, causes, is_target, md_html, when):
    """The whole page. `md_html` renders the markdown summary (owned by report.py) for the technical fold."""
    name = pathlib.Path((inv or {}).get("root", "")).name or "Lutece"
    defs = load_scenarios()
    by = {}
    for r in rows:
        by.setdefault(r["suite"], []).append(r)
    scen = sorted(by.get("scenarios", []), key=lambda r: (state(r) == "ok", (defs.get(r.get("scenario")) or {}).get("_file", ""), r["id"]))
    screens_bo = [r for r in by.get("screens", []) if surface(r) == "bo"]
    screens_env = [r for r in screens_bo if not is_target(r)]
    screens_own = [r for r in screens_bo if is_target(r)]
    ko_scen = sum(1 for r in scen if state(r) == "ko")
    H = ["<!doctype html><html lang=fr><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>",
         "<title>Rapport e2e — %s</title><style>%s</style><body><main>" % (esc(name), CSS),
         hero(name, rows, cov, inv, when),
         '<div class=topnav>%s<span class=sp></span><input id=q type=search placeholder="Filtrer…" aria-label="Filtrer les résultats">'
         '<button data-filter=all aria-pressed=true>Tout</button><button data-filter=ko aria-pressed=false>Échecs</button></div>' % "".join(
             '<a href="#%s">%s</a>' % (a, l) for a, l, present in (
                 ("defects", "À corriger", any(state(r) == "ko" for r in rows)), ("scenarios", "Scénarios", bool(scen)),
                 ("screens", "Écrans", bool(screens_own)), ("forms", "Formulaires", bool(by.get("forms"))),
                 ("fo", "Pages publiques", bool(by.get("fo"))), ("tech", "Détails techniques", True)) if present),
         defects_section(rows, is_target, causes)]
    if scen:
        H.append('<section id=scenarios data-cards><h2>Scénarios <span class=count><span class="dot %s"></span>%d, %d en échec</span></h2>'
                 '<p class=note>Un scénario est un parcours métier écrit à l\'avance : ce qu\'il ouvre, ce qu\'il saisit, ce qu\'il vérifie — dans la page et dans la base. Un scénario vert prouve le comportement ; l\'étape en rouge dit où il s\'arrête. Les valeurs <code>{{rand}}</code> sont tirées au sort à chaque exécution.</p>'
                 '<div class=scenarios>%s</div></section>' % ("ko" if ko_scen else "ok", len(scen), ko_scen,
                                                              "".join(scenario_card(r, defs.get(r.get("scenario")), causes) for r in scen)))
    H.append(screens_section(screens_own, inv, "Écrans du back-office", "screens",
                             "Chaque écran de l'artefact est ouvert avec ses paramètres et jugé sur ce qu'il rend : une page, une confirmation, un message — jamais une erreur interne, jamais une console sale. Les variantes d'un même écran (identifiants, vues) sont regroupées."))
    H.append(forms_section(by.get("forms", [])))
    fo = by.get("fo", [])
    if fo:
        H.append(screens_section(fo, inv, "Pages publiques (front-office)", "fo", "Ouvertes en visiteur anonyme, sans session.",
                                 empty="L'artefact n'expose aucune page publique : rien à ouvrir côté site."))
    if screens_env:
        H.append(screens_section(screens_env, inv, "Environnement — écrans du core et des autres plugins", "env",
                                 "Hors périmètre de l'artefact testé : ce que le site assemblé montre autour de lui. Un rouge ici se rapproche du banc du core.",
                                 collapsed=not any(state(r) == "ko" for r in screens_env)))
    tech = ['<section id=tech><details class=tech><summary>Détails techniques — synthèse, couverture, console, performance</summary><div class=prose>%s</div>' % md_html(md)]
    al = perf.get("access_log", {})
    if al.get("slowest"):
        tech.append("<div class=prose><h3>Temps serveur (access log)</h3><div class=scroll><table><thead><tr><th>Chemin</th><th class=num>n</th><th class=num>p50</th><th class=num>p95</th><th class=num>max</th></tr></thead><tbody>%s</tbody></table></div></div>" % "".join(
            "<tr><td class=mono>%s</td><td class=num>%d</td><td class=num>%s</td><td class=num>%s</td><td class=num>%s</td></tr>" % (esc(r["path"]), r["n"], r["p50_ms"], r["p95_ms"], r["max_ms"]) for r in al["slowest"]))
    if perf.get("db", {}).get("top"):
        tech.append("<div class=prose><h3>SQL</h3><div class=scroll><table><thead><tr><th class=num>n</th><th class=num>total ms</th><th class=num>moy</th><th class=num>max</th><th class=num>lignes lues</th><th class=num>sans index</th><th>requête</th></tr></thead><tbody>%s</tbody></table></div></div>" % "".join(
            "<tr><td class=num>%d</td><td class=num>%s</td><td class=num>%s</td><td class=num>%s</td><td class=num>%s</td><td class=num>%s</td><td class=mono>%s</td></tr>" % (
                t["count"], t["total_ms"], t["avg_ms"], t["max_ms"], t["rows_examined"], t["no_index"], esc(t["sql"])) for t in perf["db"]["top"]))
    if perf.get("jfr"):
        tech.append("<div class=prose><h3>JFR — méthodes chaudes</h3><pre class=block>%s</pre></div>" % esc(perf["jfr"]))
    if by.get("harness"):
        hk = sum(1 for r in by["harness"] if state(r) == "ko")
        tech.append("<div class=prose><h3>Harnais — l'oracle du banc se teste lui-même (%d, %d en échec)</h3><ul>%s</ul></div>" % (
            len(by["harness"]), hk, "".join("<li><span class='dot %s'></span> <code>%s</code>%s</li>" % (state(r), esc(r["id"]), " — " + esc((r.get("reason") or "")[:200]) if state(r) != "ok" else "") for r in by["harness"])))
    tech.append("</details></section>")
    H += tech
    H.append("</main><script>%s</script></html>" % JS)
    return "\n".join(H)
