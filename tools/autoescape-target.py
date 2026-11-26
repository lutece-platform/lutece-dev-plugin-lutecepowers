#!/usr/bin/env python3
"""autoescape-target.py — exit 0 when the project renders on a lutece-core with always-on HTML auto-escaping
(8.1.0-beta-01 and later), 1 otherwise.

Usage: autoescape-target.py [project_root | file]

The core is read from the lower bound of the lutece-core version of the pom (a ${property} resolved from its
<properties>), the lutece-core jar of an assembled webapp under target/, or the lutece-core a lutece-bom imported by
the pom manages (its pom in the local Maven repository). A file stands for the nearest project above it.
"""
import glob
import os
import re
import runpy
import sys

FLOOR = "8.1.0-beta-01"


def project_root(path):
    """The nearest directory holding a pom.xml, from path upwards; path itself when none."""
    d = os.path.abspath(path if os.path.isdir(path) else os.path.dirname(path))
    while d != os.path.dirname(d):
        if os.path.isfile(os.path.join(d, "pom.xml")):
            return d
        d = os.path.dirname(d)
    return os.path.abspath(path)


def dependency_versions(pom, artifact):
    """The versions of the <dependency> blocks of the pom naming artifact, a ${property} resolved from the pom's
    <properties>, a range read as its lower bound."""
    block = re.search(r"<properties>(.*?)</properties>", pom, re.S)
    props = dict(re.findall(r"<([\w.-]+)>\s*([^<]*?)\s*</\1>", block.group(1))) if block else {}
    found = []
    for dep in re.findall(r"<dependency>(.*?)</dependency>", pom, re.S):
        if not re.search(r"<artifactId>\s*%s\s*</artifactId>" % re.escape(artifact), dep):
            continue
        m = re.search(r"<version>\s*([^<]*?)\s*</version>", dep)
        version = m.group(1) if m else ""
        for _ in range(5):
            version = re.sub(r"\$\{([^}]+)\}", lambda p: props.get(p.group(1), p.group(0)), version)
        bound = re.match(r"[\[(]?\s*([^,\])\s$]+)", version)
        found += [bound.group(1)] if bound else []
    return found


def bom_cores(pom):
    """The lutece-core versions the lutece-bom imports of the pom manage, read in the local Maven repositories."""
    found = []
    for version in dependency_versions(pom, "lutece-bom"):
        for path in glob.glob(os.path.expanduser("~/.m2*/repository/fr/paris/lutece/starters/lutece-bom/%s/lutece-bom-%s.pom") % (version, version)):
            core = re.search(r"<lutece\.core\.version>\s*([^<\s]+)", open(path, encoding="utf-8", errors="replace").read())
            found += [core.group(1)] if core else []
    return found


def main():
    """Entry point."""
    vkey = runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "latest-lutece.py"))["vkey"]
    root = project_root(sys.argv[1] if len(sys.argv) > 1 else ".")
    found = []
    try:
        pom = open(os.path.join(root, "pom.xml"), encoding="utf-8", errors="replace").read()
        found += dependency_versions(pom, "lutece-core")
        found += bom_cores(pom)
    except OSError:
        pass
    found += [re.sub(r"^lutece-core-|\.jar$", "", os.path.basename(j))
              for j in glob.glob(os.path.join(root, "target", "*", "WEB-INF", "lib", "lutece-core-*.jar"))]
    return 0 if any(vkey(v) >= vkey(FLOOR) for v in found) else 1


if __name__ == "__main__":
    sys.exit(main())
