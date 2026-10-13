#!/usr/bin/env python3
"""i18n_unused.py — keys of a project's default bundles that nothing uses.

Usage: i18n_unused.py [project_root] [--refs DIR]

Prints `bundle:line: key` for each key of a `*_messages.properties` that no file of the project names, and exits 1
when there is one. A key counts as used when any tracked text file other than the bundles (Java, templates, JSP, JS,
XML, SQL, configuration .properties…) contains `<prefix>.<key>` or `"<key>"`, when a string literal or a `${`
template interpolation ends a stem the key starts with (`PREFIX = "demo.type."` then `PREFIX + name`), or when a
repository under --refs (default ~/.lutece-references) names `<prefix>.<key>`. Keys read by the core at runtime
(model.entity.*, validation.*, site_property.*, plugin.*) are never reported. An adminFeature.* key is not one of
them: the plugin descriptor and the core_admin_right SQL name it in full, so a key neither names is dead.
"""
import bisect
import functools
import glob
import os
import re
import subprocess
import sys
import tempfile

import bundles

RUNTIME = ("model.entity.", "validation.", "site_property.", "plugin.")
BUNDLE = re.compile(r"_messages(_\w+)?\.properties$")
SKIP_DIRS = ("target/", "e2e/", ".migration/", "node_modules/")


def project_files(root):
    """Text files of the project, bundles excluded: git's view when it is a repository, else a walk."""
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "-co", "--exclude-standard"], capture_output=True,
                             encoding="utf-8", errors="replace", check=True).stdout.split("\n")
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


@functools.lru_cache(maxsize=None)
def artifact_id(root):
    """The artifactId of a project's pom (the second one, after the parent's), or None."""
    try:
        with open(os.path.join(root, "pom.xml"), encoding="utf-8", errors="replace") as fh:
            ids = re.findall(r"<artifactId>([^<]+)</artifactId>", re.sub(r"<parent>.*?</parent>", "", fh.read(), flags=re.S))
    except OSError:
        return None
    return ids[0].strip() if ids else None


def present(hay, needles):
    """The needles found in hay (str or bytes, needles alike), as `needle in hay` would find them. A needle is looked
    up among the text following each occurrence of its anchor (up to its first dot), sorted once per anchor; a needle
    with a short anchor or no dot is searched alone."""
    groups, found = {}, set()
    dot = "." if isinstance(hay, str) else b"."
    for needle in needles:
        cut = needle.find(dot) + 1
        if cut < 3:
            if needle in hay:
                found.add(needle)
        else:
            groups.setdefault(needle[:cut], []).append(needle)
    for anchor, group in groups.items():
        width, starts, p = max(len(n) for n in group) - len(anchor), [], hay.find(anchor)
        while p >= 0:
            starts.append(hay[p + len(anchor):p + len(anchor) + width])
            p = hay.find(anchor, p + 1)
        starts.sort()
        for needle in group:
            rest = needle[len(anchor):]
            i = bisect.bisect_left(starts, rest)
            if i < len(starts) and starts[i].startswith(rest):
                found.add(needle)
    return found


def quoted(text, keys):
    """The keys `"key"` names in text, as `'"' + key + '"' in text` would find them."""
    plain = {k for k in keys if '"' not in k}
    found = {m.group(1) for m in re.finditer(r'"([^"]*)(?=")', text) if m.group(1) in plain}
    return found | {k for k in keys if '"' in k and '"' + k + '"' in text}


def used_elsewhere(refs, fulls, own):
    """The keys of fulls that a reference repository other than the project, or a copy of it (same artifactId), names."""
    if not refs or not os.path.isdir(refs) or not fulls:
        return set()
    with tempfile.NamedTemporaryFile("w", suffix=".keys", delete=False, encoding="utf-8") as patterns:
        patterns.write("\n".join(sorted(fulls)) + "\n")
    try:
        out = subprocess.run(["grep", "-rlF", "-f", patterns.name, "--exclude=*_messages*.properties", "--exclude-dir=target", refs],
                             capture_output=True, encoding="utf-8", errors="replace").stdout.splitlines()
    finally:
        os.unlink(patterns.name)
    mine = artifact_id(own)
    encoded = {k.encode("utf-8"): k for k in fulls}
    found = set()
    for o in out:
        o = os.path.normpath(o)
        repo = os.path.join(refs, os.path.relpath(o, refs).split(os.sep)[0])
        if os.path.basename(own) in o.split(os.sep) or (mine and artifact_id(repo) == mine):
            continue
        with open(o, "rb") as handle:
            data = handle.read()
        found.update(encoded[k] for k in present(data, encoded))
    return found


def keys_of(bundle):
    """(line, key) of each entry of a bundle."""
    for n, key, _ in bundles.entries(bundle):
        yield n, key


def unused(root, refs):
    """(bundle, line, key) of every unused key of the project's default bundles."""
    text = read_all(root, project_files(root))
    stems = stems_of(text)
    entries = []
    for bundle in sorted(glob.glob(os.path.join(root, "src/java/**/resources/*_messages.properties"), recursive=True)):
        prefix = os.path.basename(bundle)[:-len("_messages.properties")]
        entries.extend((bundle, n, key, prefix) for n, key in keys_of(bundle))
    asked = [(key, prefix + "." + key) for _, _, key, prefix in entries if key and not key.startswith(RUNTIME)]
    named = present(text, {full for _, full in asked})
    bare = quoted(text, {key for key, _ in asked})
    candidates = []
    for bundle, n, key, prefix in entries:
        full = prefix + "." + key
        if not key or key.startswith(RUNTIME) or full in named or key in bare:
            continue
        if any(full.startswith(s) or key.startswith(s) or (prefix + "." in s and key.startswith(s.split(prefix + ".", 1)[1]))
               for s in stems):
            continue
        candidates.append((bundle, n, key, full))
    elsewhere = used_elsewhere(refs, {full for _, _, _, full in candidates}, os.path.abspath(root))
    for bundle, n, key, full in candidates:
        if full not in elsewhere:
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
