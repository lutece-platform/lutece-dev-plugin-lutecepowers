#!/usr/bin/env python3
"""Derives EARS requirements (Easy Approach to Requirements Syntax) from the inventory and the scenarios,
so every screen and action of the back office has a testable statement and the report can show coverage
per requirement. Generated, never hand-edited: the scenario files carry the business intent (title, req).

Usage: ears.py artifacts/inventory.json scenarios/ > artifacts/requirements.ears.md
"""
import json
import pathlib
import sys

import yaml


def main():
    inv = json.loads(pathlib.Path(sys.argv[1]).read_text())
    scen_dir = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else None
    scenarios = []
    if scen_dir and scen_dir.exists():
        for f in sorted(scen_dir.glob("*.yaml")):
            scenarios += (yaml.safe_load(f.read_text()) or {}).get("scenarios", [])
    by_req = {}
    for sc in scenarios:
        by_req.setdefault(sc.get("req", "UNMAPPED"), []).append(sc)

    print("# Exigences EARS — back office\n")
    print("Générées depuis l'inventaire statique (%d fonctionnalités, %d écrans, %d actions) et %d scénarios.\n"
          % (inv["stats"]["features"], inv["stats"]["screens"], inv["stats"]["actions"], len(scenarios)))
    print("## Ubiquitaires\n")
    print("- **REQ-U1** Le back office SHALL répondre à chaque écran par une page HTML 200 sans page d'erreur Lutece ni erreur serveur. *(suite screens)*")
    print("- **REQ-U2** WHILE un écran est affiché, le navigateur SHALL ne journaliser aucune erreur JavaScript, aucune erreur console et aucune sous-requête en échec. *(suite screens)*")
    print("- **REQ-U3** WHEN un formulaire est soumis avec des valeurs plausibles, le back office SHALL répondre par un écran ou un message Lutece, jamais par une page d'erreur. *(suite forms)*")
    print("- **REQ-U4** IF l'agent n'est pas authentifié, THEN le back office SHALL rediriger tout écran protégé vers AdminLogin.jsp. *(scenario session_logout)*")
    print("- **REQ-U5** WHILE le volume de données est celui du profil large, chaque écran SHALL rester sous le budget de temps de réponse (p95) défini dans tools/report.py. *(perf)*\n")
    print("## Par fonctionnalité\n")
    screens_by_right = {}
    for s in inv["screens"]:
        screens_by_right.setdefault(s.get("right") or "-", []).append(s)
    actions_by_right = {}
    for a in inv["actions"]:
        actions_by_right.setdefault(a.get("right") or "-", []).append(a)
    for f in inv["features"]:
        r = f["right"]
        print("### %s\n" % r)
        print("- **%s-1** WHEN l'agent ouvre l'entrée `%s`, le back office SHALL afficher l'écran de la fonctionnalité." % (r, f["url"] or "(sans URL, tableau de bord)"))
        n = 2
        for s in screens_by_right.get(r, []):
            print("- **%s-%d** WHEN l'agent ouvre `%s`, le back office SHALL afficher l'écran `%s` sans erreur." % (r, n, s["url"], s["method"] or s["id"])); n += 1
        for a in actions_by_right.get(r, []):
            print("- **%s-%d** WHEN l'agent soumet `%s`, le back office SHALL exécuter `%s` et répondre par un écran ou un message." % (r, n, a["url"], a["method"] or a["id"])); n += 1
        for sc in by_req.get(r, []):
            print("- **%s-S** %s *(scenario %s, %d étapes)*" % (r, sc.get("title", sc["id"]), sc["id"], len(sc.get("steps", []))))
        print()
    if by_req.get("UNMAPPED") or any(k not in {f["right"] for f in inv["features"]} for k in by_req):
        print("## Scénarios hors fonctionnalité inventoriée\n")
        for k, scs in by_req.items():
            if k not in {f["right"] for f in inv["features"]}:
                for sc in scs:
                    print("- **%s** %s *(scenario %s)*" % (k, sc.get("title", sc["id"]), sc["id"]))


if __name__ == "__main__":
    main()
