#!/usr/bin/env python3
"""latest-lutece.py — the latest Lutece 8 version of Lutece artefacts, read in the Lutece repositories, never written
by hand anywhere.

Usage:
  latest-lutece.py snapshot [--line N] <groupId:artifactId> ...   the highest -SNAPSHOT of the line N, with its last build
  latest-lutece.py release [--line N] <groupId:artifactId> ...    the highest release of the line N
  latest-lutece.py bom [--line N] <groupId:artifactId> ...        the release of a BOM that manages the highest
                                                                  lutece-core, the highest of them when several do

A version is of the line N when its pom has lutece-global-pom N.x as parent; lutece-core, and an artefact whose
parent is not lutece-global-pom (a parent pom, a BOM), by their own major N.

N is the Lutece line, 8 by default (7 for an artefact a Lutece 7 site runs).

Prints one line per artefact: groupId:artifactId:version[:build], the build being the timestamp-number of the last
snapshot deployed (e.g. 20261002.102953-285). The repository's own <latest> is the last version deployed, not the
highest: a v7 maintenance snapshot deployed after the v8 one would win, hence the check of each candidate's parent.
The answers are cached an hour in ~/.cache/lutecepowers/latest-lutece-2.json. When the repository cannot be reached,
the local Maven repository answers instead, with a warning on stderr. Exit 1 when an artefact has no version of the line.

A BOM is chosen by the core it manages, not by its own number: lutece-bom 8.0.0-RC-01 sorts above 8.0.0-beta-03 in the
Maven order and manages an older core.
"""
import json
import os
import pathlib
import re
import sys
import time
import urllib.request

SNAPSHOTS = os.environ.get("LUTECE_SNAPSHOT_REPO", "https://dev.lutece.paris.fr/snapshot_repository")
RELEASES = os.environ.get("LUTECE_RELEASE_REPO", "https://dev.lutece.paris.fr/maven_repository")
M2 = pathlib.Path(os.environ.get("M2_REPO", pathlib.Path.home() / ".m2" / "repository"))
CACHE = pathlib.Path(os.environ.get("LUTECE_LATEST_CACHE", pathlib.Path.home() / ".cache" / "lutecepowers" / "latest-lutece-2.json"))
TTL = 3600
LINE = "8"


QUALIFIERS = {"alpha": 0, "a": 0, "beta": 1, "b": 1, "milestone": 2, "m": 2, "rc": 3, "cr": 3, "snapshot": 4}


def vkey(v):
    """Sort key of a Maven version: numbers compared as numbers; a qualified version (alpha, beta, milestone, rc,
    SNAPSHOT, in that order) sorts before its release, two qualified ones by the numbers of their qualifier."""
    base, _, qual = v.partition("-")
    nums = [int(x) for x in re.findall(r"\d+", base)]
    nums += [0] * (3 - len(nums))
    q = qual.lower()
    rank = QUALIFIERS.get(re.match(r"[a-z]*", q).group(0), 4) if q else 5
    return nums, rank, [int(x) for x in re.findall(r"\d+", q)]


def fetch(url):
    """The text at an url, None when it cannot be read."""
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 - unreachable, missing: the caller falls back
        return None


def path(ga):
    """The repository path of groupId:artifactId."""
    g, a = ga.split(":")
    return "%s/%s" % (g.replace(".", "/"), a)


def parent_major(pom):
    """The major version of lutece-global-pom when it is the pom's parent, else None."""
    p = re.search(r"<parent>(.*?)</parent>", pom or "", re.S)
    if p and "<artifactId>lutece-global-pom</artifactId>" in p.group(1):
        v = re.search(r"<version>\s*([^<\s]+)", p.group(1))
        return v.group(1).split(".")[0] if v else None
    return None


def in_line(ga, version, read_pom):
    """True when this version belongs to the Lutece line asked: by the lutece-global-pom parent of its pom (read_pom()
    returns it), lutece-core and an artefact without that parent by their own major."""
    major = None if ga.endswith(":lutece-core") else parent_major(read_pom())
    return (major or version.split(".")[0]) == LINE


def remote_snapshot(ga):
    """(version, build) of the highest snapshot of the line in the snapshot repository; None when unreachable."""
    meta = fetch("%s/%s/maven-metadata.xml" % (SNAPSHOTS, path(ga)))
    if meta is None:
        return None
    a = ga.split(":")[1]
    for v in sorted(set(re.findall(r"<version>([^<]+-SNAPSHOT)</version>", meta)), key=vkey, reverse=True):
        vmeta = fetch("%s/%s/%s/maven-metadata.xml" % (SNAPSHOTS, path(ga), v)) or ""
        ts = re.search(r"<timestamp>([^<]+)</timestamp>\s*<buildNumber>([^<]+)</buildNumber>", vmeta)
        build = "%s-%s" % ts.groups() if ts else ""
        if in_line(ga, v, lambda: fetch("%s/%s/%s/%s-%s.pom" % (SNAPSHOTS, path(ga), v, a, v.replace("SNAPSHOT", build))) if build else None):
            return v, build
    return "", ""


def releases(ga):
    """The release versions of groupId:artifactId in the release repository; None when unreachable."""
    meta = fetch("%s/%s/maven-metadata.xml" % (RELEASES, path(ga)))
    if meta is None:
        return None
    return {v for v in re.findall(r"<version>([^<]+)</version>", meta) if "SNAPSHOT" not in v}


def release_pom(ga, v):
    """The pom text of the release v of groupId:artifactId, None when it cannot be read."""
    return fetch("%s/%s/%s/%s-%s.pom" % (RELEASES, path(ga), v, ga.split(":")[1], v))


def remote_release(ga):
    """The highest release of the line in the release repository; None when unreachable."""
    vs = releases(ga)
    if vs is None:
        return None
    for v in sorted(vs, key=vkey, reverse=True)[:12]:
        if in_line(ga, v, lambda: release_pom(ga, v)):
            return v, ""
    return "", ""


def managed_core(pom):
    """The lutece-core version a BOM pom manages, its own properties resolved; None when it manages none."""
    d = re.search(r"<artifactId>\s*lutece-core\s*</artifactId>\s*<version>\s*([^<\s]+)", pom or "")
    if not d:
        return None
    v = d.group(1)
    p = re.fullmatch(r"\$\{(.+)\}", v)
    if p:
        m = re.search(r"<(%s)>\s*([^<\s]+)\s*</\1>" % re.escape(p.group(1)), pom)
        return m.group(2) if m else None
    return v


def best_bom(poms):
    """Of {version: pom text}, the BOM release of the line whose managed lutece-core is the highest, the highest
    version among those that manage the same core; "" when none of the line manages one."""
    managed = {v: c for v, pom in poms.items() if in_line("", v, lambda: pom) and (c := managed_core(pom))}
    return max(managed, key=lambda v: (vkey(managed[v]), vkey(v))) if managed else ""


def remote_bom(ga):
    """The BOM release of the line that manages the highest lutece-core (best_bom); None when unreachable."""
    vs = releases(ga)
    if vs is None:
        return None
    return best_bom({v: release_pom(ga, v) or "" for v in vs}), ""


def local(ga, kind):
    """The highest version of the line in the local Maven repository, for an offline machine."""
    d = M2 / path(ga)
    a = ga.split(":")[1]
    if kind == "bom":
        poms = {v.name: v / ("%s-%s.pom" % (a, v.name)) for v in (d.iterdir() if d.is_dir() else []) if not v.name.endswith("-SNAPSHOT")}
        return best_bom({v: f.read_text(errors="replace") for v, f in poms.items() if f.is_file()}), ""
    for v in sorted((p.name for p in d.iterdir() if p.is_dir()) if d.is_dir() else [], key=vkey, reverse=True):
        if (kind == "snapshot") != v.endswith("-SNAPSHOT"):
            continue
        poms = sorted((d / v).glob(a + "-*.pom"))
        if in_line(ga, v, lambda: poms[-1].read_text(errors="replace") if poms else ""):
            return v, ""
    return "", ""


def main():
    """Entry point."""
    global LINE
    args = sys.argv[1:]
    if len(args) > 2 and args[1] == "--line":
        LINE = args.pop(2)
        args.pop(1)
    if len(args) < 2 or args[0] not in ("snapshot", "release", "bom") or not LINE.isdigit():
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    kind = args[0]
    try:
        cache = json.loads(CACHE.read_text())
    except (OSError, ValueError):
        cache = {}
    rc = 0
    for ga in args[1:]:
        key = "%s %s" % (kind, ga) if LINE == "8" else "%s %s %s" % (kind, LINE, ga)
        hit = cache.get(key)
        if hit and time.time() - hit["t"] < TTL:
            v, build = hit["v"], hit["b"]
        else:
            got = {"snapshot": remote_snapshot, "release": remote_release, "bom": remote_bom}[kind](ga)
            if got is None:
                print("latest-lutece: repository unreachable, %s from the local Maven repository" % ga, file=sys.stderr)
                v, build = local(ga, kind)
            else:
                v, build = got
                cache[key] = {"v": v, "b": build, "t": time.time()}
        if not v:
            print("latest-lutece: no Lutece %s %s of %s" % (LINE, kind, ga), file=sys.stderr)
            rc = 1
            continue
        print("%s:%s%s" % (ga, v, ":" + build if build else ""))
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    tmp = CACHE.with_suffix(".%d.tmp" % os.getpid())
    tmp.write_text(json.dumps(cache))
    os.replace(tmp, CACHE)
    sys.exit(rc)


if __name__ == "__main__":
    main()
