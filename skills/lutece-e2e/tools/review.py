#!/usr/bin/env python3
"""Visual review of the run: what the assertions cannot judge.

The suites prove behaviour (the DOM classifies, the database confirms) and `lutece.render_check` catches the
rendering defects a machine can see. What is left needs eyes: does the screen follow the design system, is the
layout sound, do screens of the same family look alike. This tool makes that step finite and verifiable.

  review.py todo     -> artifacts/review-todo.md : the deduplicated, prioritised list of screenshots to look at
  review.py check    -> exit 0 when artifacts/review.md carries a verdict for every group, else exit 7

Screens are grouped by (url path, kind): the same screen opened with twenty different ids is one group, reviewed
once. Groups showing a mechanical rendering finding come first, then the unusual kinds, then the rest.
"""
import argparse
import collections
import glob
import hashlib
import json
import pathlib
import re
import sys


def parse_args(argv):
    """The command, todo by default; --help prints the usage and exits before anything is read or written."""
    p = argparse.ArgumentParser(prog="review.py", description="Visual review of the run, in the project's e2e folder (E2E_DIR).")
    p.add_argument("cmd", nargs="?", default="todo", choices=("todo", "check"),
                   help="todo: write artifacts/review-todo.md; check: exit 7 until artifacts/review.md judges every group")
    return p.parse_args(argv).cmd


CMD = parse_args(sys.argv[1:]) if __name__ == "__main__" else None
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tests"))
import lutece  # noqa: E402
E2E = lutece.E2E
A = E2E / "artifacts"


CHECKLIST = """Pour chaque groupe, ouvrir la capture et répondre :
1. **Charte** — thème attendu appliqué (en-tête, menu, pied), typographie et composants du design system, aucune
   page « brute » sans style.
2. **Mise en page** — rien ne se chevauche, rien n'est tronqué, pas de débordement, les colonnes sont alignées.
3. **Contenu** — aucun libellé technique visible, aucune valeur `null`, les listes vides affichent un message et
   non un tableau cassé, les libellés sont traduits.
4. **Cohérence** — cet écran ressemble aux autres de sa famille (même gabarit de liste, de formulaire, d'action).
5. **Lisibilité** — hiérarchie visuelle claire, actions principales identifiables.
"""


def rows():
    out = []
    for f in sorted((A / "results").glob("*.jsonl")):
        out += [json.loads(l) for l in f.read_text().splitlines() if l.strip()]
    return out


def _rank(r, shot):
    """Representative priority: a mechanical finding first, then a parameterised call.

    A screen opened without its identifiers usually redirects to a guard page, so its capture shows
    something else entirely; the parameterised call is the one that renders the screen.
    """
    return (1 if _findings(r) else 0) * 2 + (1 if "?" in (r.get("url") or "") else 0)


def _better(e, r, shot):
    """Whether this row is a better representative than the one already held."""
    if "rank" not in e:
        e["rank"] = -1
    n = _rank(r, shot)
    if n > e["rank"]:
        e["rank"] = n
        return True
    return False


def _findings(r):
    """Rendering findings that belong to the artefact under test.

    A front-office row carries `render_own`: the findings left once the bare portal's own defects are
    subtracted. Without it the review sends the reviewer after the site theme's broken footer logo, which no
    migration can fix, and the findings that do belong to the artefact are lost in the noise."""
    return r.get("render_own") if r.get("render_own") is not None else (r.get("render") or [])


def _digest(shot):
    """Content hash of a capture, or None when the file is gone."""
    f = A / shot
    return hashlib.md5(f.read_bytes()).hexdigest() if f.exists() else None


def _in_scope():
    """The bench's scope predicate (tests/lutece.py): the review judges the artefact's own screens, never the
    hundreds of core screens a widened crawl (E2E_SCOPE=all) also captured — those are the environment's."""
    try:
        return lutece.scope()
    except Exception:  # noqa: BLE001 - no inventory, no scope: judge everything
        return lambda u: True


def _with_review_shots(rows_):
    """The rows plus one row per capture a scenario took on its way: every screen a navigating step reached (a
    form, a confirmation, a list holding the data the scenario created, an error message) and every explicit
    `shot:` step, often a screen only a signed-in user reaches. The crawl alone sees the screens a url opens; the
    screens a scenario reaches carry the data and the states where rendering defects hide."""
    out = list(rows_)
    for r in rows_:
        for s in r.get("review_shots") or []:
            out.append({"suite": "scenarios", "id": r["id"], "url": s["url"], "kind": s.get("kind") or "shot",
                        "screenshot": s["shot"], "status": r.get("status")})
    return out


def groups():
    """One review group per (url path, kind) of the artefact under test, with a representative screenshot and
    the urls it stands for. Scenario captures count as the artefact's whatever their url, except the failure capture of
    a core defect scenario: a known red of the core, not a rendering of the artefact, and different on every run."""
    g = collections.OrderedDict()
    in_scope = _in_scope()
    for r in _with_review_shots(rows()):
        shot = r.get("screenshot")
        if not shot or r.get("suite") not in ("screens", "fo", "forms", "scenarios"):
            continue
        if r.get("core_defect"):
            continue
        if r.get("failed_step_kind") == "http":
            continue
        if r.get("suite") != "scenarios" and not in_scope(r.get("url") or r.get("screen") or ""):
            continue
        path = lutece.nav_key(r.get("url") or r.get("screen") or r["id"])
        key = (path, r.get("kind") or "?")
        e = g.setdefault(key, {"path": path, "kind": key[1], "suite": r["suite"], "shot": shot,
                               "urls": set(), "render": [], "status": set()})
        e["urls"].add(r.get("url") or r["id"])
        e["render"] = e["render"] or _findings(r)
        e["status"].add(r.get("status"))
        if _better(e, r, shot):
            e["shot"] = shot
    ordered = sorted(g.values(), key=lambda e: (not e["render"],
                                                e["kind"] in ("screen", "fo", "confirmation"),
                                                e["path"]))
    for i, e in enumerate(ordered, 1):
        e["id"] = "G%03d" % i
    return ordered


def key_stamp():
    """Source key of the run (fingerprint.json, tools/source-key.py), or None: a review is valid for that key only."""
    try:
        return json.loads((A / "fingerprint.json").read_text()).get("source_key") or None
    except Exception:  # noqa: BLE001 - no fingerprint: nothing to tie the review to
        return None


REVIEWED = A / "review-shots.json"
"""Capture digest of each group (by path and kind) at the last accepted review."""


def reviewed_digests():
    """The capture digests the last accepted review judged, keyed by group path and kind."""
    try:
        return json.loads(REVIEWED.read_text())
    except Exception:  # noqa: BLE001 - no accepted review yet
        return {}


def changed_since_review(gs):
    """Ids of the groups whose capture differs from the one the last accepted review judged."""
    before = reviewed_digests()
    return [e["id"] for e in gs if before and before.get("%s|%s" % (e["path"], e["kind"])) != _digest(e["shot"])]


def shots_stamp(gs):
    """Fingerprint of the captures a review judges (one per group), or None when one is missing: a review stays valid
    while its captures are byte for byte the same, whatever else changed in the sources."""
    digests = ["%s:%s" % (e["id"], _digest(e["shot"])) for e in gs]
    if not digests or any(d.endswith(":None") for d in digests):
        return None
    return hashlib.md5("\n".join(sorted(digests)).encode()).hexdigest()[:16]


def todo():
    gs = groups()
    L = ["# Revue visuelle — %d groupes" % len(gs), "",
         "Les suites prouvent le comportement ; cette étape juge le **rendu**. Un groupe = un écran, quelles que",
         "soient les données. Ouvrir la capture indiquée, répondre à la grille, puis reporter un verdict par",
         "groupe dans `artifacts/review.md` (une ligne `- [x] G012 ok` ou `- [x] G012 defect: …`).", "",
         CHECKLIST, "",
         "Sources jugées : `%s` — recopier en tête de `artifacts/review.md` les lignes `key: %s` et `shots: %s` : "
         "une revue vaut pour les sources qu'elle a regardées, ou tant que ses captures restent identiques."
         % (key_stamp() or "?", key_stamp() or "?", shots_stamp(gs) or "?"), "",
         "| Groupe | Écran | Type | Constat mécanique | Capture |", "|---|---|---|---|---|"]
    seen = {}
    changed = set(changed_since_review(gs))
    for e in gs:
        d = _digest(e["shot"])
        twin = seen.get(d)
        if d and twin is None:
            seen[d] = e["id"]
        notes = "; ".join(e["render"])[:90] or "—"
        if twin:
            notes = ("%s — capture identique à %s (probable redirection)"
                     % ("" if notes == "—" else notes, twin)).strip(" —")
        if e["id"] in changed:
            notes = ("%s — capture changée depuis la dernière revue" % ("" if notes == "—" else notes)).strip(" —")
        L.append("| %s | `%s`%s | %s | %s | `%s` |" % (
            e["id"], e["path"], (" (+%d variantes)" % (len(e["urls"]) - 1)) if len(e["urls"]) > 1 else "",
            e["kind"], notes, (A / e["shot"]).relative_to(A)))
    (A / "review-todo.md").write_text("\n".join(L) + "\n")
    flagged = sum(1 for e in gs if e["render"])
    print("review-todo.md : %d groupes (%d avec un constat mécanique), %d captures couvertes"
          % (len(gs), flagged, sum(len(e["urls"]) for e in gs)))
    return gs


def check():
    gs = groups()
    # An artefact with no screen of its own — a servlet filter, a session listener, a library proven through a
    # consumer — produces no capture. There is nothing for an eye to judge, and demanding a review.md anyway only
    # buys an empty file. The coverage section of summary.md still reports the zero.
    if not gs:
        print("revue visuelle : aucun écran capturé, rien à juger (artefact sans écran propre)")
        return 0
    f = A / "review.md"
    if not f.exists():
        print("REVUE VISUELLE NON FAITE : %d groupes à examiner, artifacts/review.md absent "
              "(voir artifacts/review-todo.md)" % len(gs))
        return 7
    stamp, shots = key_stamp(), shots_stamp(gs)
    text = f.read_text()
    if not (stamp and ("key: %s" % stamp) in text) and not (shots and ("shots: %s" % shots) in text):
        changed = changed_since_review(gs)
        print("REVUE VISUELLE D'AUTRES SOURCES : artifacts/review.md ne porte ni la ligne `key: %s` de ce run "
              "(fingerprint.json) ni la ligne `shots: %s` de ses captures ; refaire la revue sur les captures qui ont "
              "changé%s" % (stamp or "?", shots or "?", (" : %s (review-todo.md)" % ", ".join(changed)) if changed else ""))
        return 7
    done = set(re.findall(r"\bG\d{3}\b", f.read_text()))
    missing = [e["id"] for e in gs if e["id"] not in done]
    if missing:
        print("REVUE VISUELLE INCOMPLÈTE : %d/%d groupes sans verdict (%s%s)"
              % (len(missing), len(gs), ", ".join(missing[:8]), "…" if len(missing) > 8 else ""))
        return 7
    REVIEWED.write_text(json.dumps({"%s|%s" % (e["path"], e["kind"]): _digest(e["shot"]) for e in gs}, indent=1))
    print("revue visuelle : %d/%d groupes couverts" % (len(gs), len(gs)))
    return 0


if __name__ == "__main__":
    # `todo() and 0` exited with the list itself when there was no group at all: python printed it and returned 1,
    # and run.sh, which runs under `set -e`, stopped right after the report — no server-error check, no review.
    if CMD == "check":
        sys.exit(check())
    todo()
    sys.exit(0)
