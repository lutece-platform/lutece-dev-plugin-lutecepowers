#!/usr/bin/env python3
"""i18n_unused.py — keys of a project's default bundles that nothing uses.

Usage: i18n_unused.py [project_root] [--refs DIR]

Prints `bundle:line: key` for each key of a `*_messages.properties` that no file of the project names, and exits 1
when there is one. A key counts as used when any tracked text file other than the bundles (Java, templates, JSP, JS,
XML, SQL, configuration .properties…) contains `<prefix>.<key>` or `"<key>"`, when a string literal or a `${`
template interpolation ends a stem the key starts with (`PREFIX = "demo.type."` then `PREFIX + name`), or when a
repository under --refs (default ~/.lutece-references) names `<prefix>.<key>`. Keys read by the core at runtime
(model.entity.*, validation.*, site_property.*, plugin.*, adminFeature.*) are never reported.
"""
import glob
import os
import re
import subprocess
import sys

import bundles

RUNTIME = ("model.entity.", "validation.", "site_property.", "plugin.", "adminFeature.")
BUNDLE = re.compile(r"_messages(_\w+)?\.properties$")
SKIP_DIRS = ("target/", "e2e/", ".migration/", "node_modules/")


def project_files(root):
    """Text files of the project, bundles excluded: git's view when it is a repository, else a walk."""
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "-co", "--exclude-standard"], capture_output=True,
                             text=True, check=True).stdout.split("\n")
    except (OSError, subprocess.CalledProcessError):
        out = [os.path.relpath(os.path.join(d, f), root) for d, _, fs in os.walk(root) for f in fs]
    return [f for f in out if f and not f.startswith(SKIP_DIRS) and not BUNDLE.search(f)
            and os.path.isfile(os.path.join(root, f))]


def read_all(root, files):
    """Concatenated content of the files, binary ones skipped."""
    parts = []
    for f in files:
        try:
            data = open(os.path.join(root, f), "rb").read()
        except OSError:
            continue
        if b"\0" not in data[:4096]:
            parts.append(data.decode("utf-8", errors="replace"))
    return "\n".join(parts)


def stems_of(text):
    """Prefixes a key may be built from: literals ending with . or _ and the static part of #i18n{x.${y}}."""
    found = set(re.findall(r'"([A-Za-z][\w.-]*[._])"', text))
    found |= set(re.findall(r"'([A-Za-z][\w.-]*[._])'", text))
    found |= set(re.findall(r"#i18n\{([\w.-]+[._])\$\{", text))
    found |= set(re.findall(r"=\s*([A-Za-z][\w.-]*[._])\s*$", text, re.M))
    return {s for s in found if s.count(".") >= 1 and len(s) > 3}


def used_elsewhere(refs, full, own):
    """True when a reference repository other than the project names the key."""
    if not refs or not os.path.isdir(refs):
        return False
    out = subprocess.run(["grep", "-rlF", "--exclude=*_messages*.properties", "--exclude-dir=target", full, refs],
                         capture_output=True, text=True).stdout.split()
    return any(os.path.basename(own) not in o.split(os.sep) for o in out)


def keys_of(bundle):
    """(line, key) of each entry of a bundle."""
    for n, key, _ in bundles.entries(bundle):
        yield n, key


def unused(root, refs):
    """(bundle, line, key) of every unused key of the project's default bundles."""
    text = read_all(root, project_files(root))
    stems = stems_of(text)
    for bundle in sorted(glob.glob(os.path.join(root, "src/java/**/resources/*_messages.properties"), recursive=True)):
        prefix = os.path.basename(bundle)[:-len("_messages.properties")]
        for n, key in keys_of(bundle):
            full = prefix + "." + key
            if not key or key.startswith(RUNTIME) or full in text or '"' + key + '"' in text:
                continue
            if any(full.startswith(s) or key.startswith(s) or (prefix + "." in s and key.startswith(s.split(prefix + ".", 1)[1]))
                   for s in stems):
                continue
            if used_elsewhere(refs, full, os.path.abspath(root)):
                continue
            yield os.path.relpath(bundle, root), n, key


def main():
    """Entry point."""
    args = sys.argv[1:]
    refs = os.path.expanduser("~/.lutece-references")
    if "--refs" in args:
        i = args.index("--refs")
        refs = args[i + 1]
        del args[i:i + 2]
    root = args[0] if args else "."
    found = 0
    for bundle, n, key in unused(root, refs):
        print("%s:%d: %s" % (bundle, n, key))
        found += 1
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
