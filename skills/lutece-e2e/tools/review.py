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
import collections
import glob
import hashlib
import json
import pathlib
import re
import sys

E2E = pathlib.Path(__file__).resolve().parents[1]
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


def groups():
    """One review group per (url path, kind), with a representative screenshot and the urls it stands for."""
    g = collections.OrderedDict()
    for r in rows():
        shot = r.get("screenshot")
        if not shot or r.get("suite") not in ("screens", "fo", "forms", "scenarios"):
            continue
        path = (r.get("url") or r.get("screen") or r["id"]).split("?")[0]
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


def todo():
    gs = groups()
    L = ["# Revue visuelle — %d groupes" % len(gs), "",
         "Les suites prouvent le comportement ; cette étape juge le **rendu**. Un groupe = un écran, quelles que",
         "soient les données. Ouvrir la capture indiquée, répondre à la grille, puis reporter un verdict par",
         "groupe dans `artifacts/review.md` (une ligne `- [x] G012 ok` ou `- [x] G012 defect: …`).", "",
         CHECKLIST, "",
         "| Groupe | Écran | Type | Constat mécanique | Capture |", "|---|---|---|---|---|"]
    seen = {}
    for e in gs:
        d = _digest(e["shot"])
        twin = seen.get(d)
        if d and twin is None:
            seen[d] = e["id"]
        notes = "; ".join(e["render"])[:90] or "—"
        if twin:
            notes = ("%s — capture identique à %s (probable redirection)"
                     % ("" if notes == "—" else notes, twin)).strip(" —")
        L.append("| %s | `%s`%s | %s | %s | `%s` |" % (
            e["id"], e["path"], (" (+%d variantes)" % (len(e["urls"]) - 1)) if len(e["urls"]) > 1 else "",
            e["kind"], notes, e["shot"]))
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
    done = set(re.findall(r"\bG\d{3}\b", f.read_text()))
    missing = [e["id"] for e in gs if e["id"] not in done]
    if missing:
        print("REVUE VISUELLE INCOMPLÈTE : %d/%d groupes sans verdict (%s%s)"
              % (len(missing), len(gs), ", ".join(missing[:8]), "…" if len(missing) > 8 else ""))
        return 7
    print("revue visuelle : %d/%d groupes couverts" % (len(gs), len(gs)))
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "todo"
    # `todo() and 0` exited with the list itself when there was no group at all: python printed it and returned 1,
    # and run.sh, which runs under `set -e`, stopped right after the report — no server-error check, no review.
    if cmd == "check":
        sys.exit(check())
    todo()
    sys.exit(0)
