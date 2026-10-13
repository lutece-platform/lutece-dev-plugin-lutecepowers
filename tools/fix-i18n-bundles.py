#!/usr/bin/env python3
"""Repairs the i18n bundles of a Lutece project, in place, for the defects verify-migration reports as I18N05, I18N06,
I18N01, I18N10 and I18N09, in that order:

1. a bundle suffixed with a country code (`_cz`, `_dk`, `_se`...) is renamed to its language code (the git index is left alone)
   (merged into the language bundle when both exist, the language bundle winning);
2. a `key>value` line gets its `=` back;
3. a key repeating the bundle prefix (`myplugin.name` in myplugin_messages) that the project asks for as written
   loses the prefix, or is removed when the bundle already declares the short key (a key nothing asks for is dead:
   `--drop`);
4. a key declared twice in a bundle keeps its last occurrence only, the one java.util.Properties already shows;
5. in a translation, a key the default bundle does not declare is removed: nothing asks for it, it never shows.

`--drop <file>` also removes, from every language, the keys the file lists one per line (the I18N08 keys confirmed
dead once i18n_unused.py has been run against every consumer of the bundle).

`--add <file>` sets keys, one `<bundle>[_<lang>]:<key>=<value>` per line in UTF-8 (`contact:manage.title=Contacts`,
`contact_fr:manage.title=Contacts du site`): the key is replaced where the bundle declares it, appended otherwise, the
value written with \\uXXXX escapes for every non-ASCII character and the line ending of the file.

Bytes are kept as they are (latin-1 round trip), line endings too. Prints one line per change; `--dry-run` runs on a copy and only prints.

    fix-i18n-bundles.py [--dry-run] [--drop <keys_file>] [--add <keys_file>] <project_dir>
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

import bundles

COUNTRY_TO_LANGUAGE = {"cz": "cs", "dk": "da", "se": "sv", "gr": "el", "jp": "ja", "cn": "zh", "ua": "uk", "kr": "ko",
                       "ee": "et", "si": "sl", "rs": "sr", "al": "sq"}
ARROW = re.compile(r"^([^=:\s>]+)>")


def read(path):
    """The physical lines of a file, line endings kept."""
    return open(path, encoding="latin-1", newline="").read().splitlines(keepends=True)


def write(path, lines):
    """Writes the lines back."""
    open(path, "w", encoding="latin-1", newline="").write("".join(lines))


def rename_country_bundles(root):
    """Step 1: country suffixes become language suffixes."""
    for path in sorted(glob.glob(os.path.join(root, "src/java/**/*_messages_*.properties"), recursive=True)):
        m = re.match(r"(.*_messages)_([a-z]{2})\.properties$", path)
        if not m or m.group(2) not in COUNTRY_TO_LANGUAGE:
            continue
        target = "%s_%s.properties" % (m.group(1), COUNTRY_TO_LANGUAGE[m.group(2)])
        print("I18N05 %s -> %s" % (os.path.relpath(path, root), os.path.basename(target)))
        if os.path.exists(target):
            known = bundles.keys(target)
            extra = [ln for s, e, text in bundles.spans(path) for ln in read(path)[s - 1:e]
                     if bundles.KEY.match(text) and bundles.KEY.match(text).group(1) not in known]
            lines = read(target)
            if lines and not lines[-1].endswith(("\n", "\r")):
                lines[-1] += "\n"
            write(target, lines + extra)
            os.remove(path)
        else:
            os.rename(path, target)


def fix_arrows(path, root):
    """Step 2: `key>value` becomes `key=value`."""
    lines = read(path)
    changed = False
    for start, end, text in bundles.spans(path):
        if start != end:
            continue
        m = ARROW.match(text)
        if m:
            raw = lines[start - 1]
            lines[start - 1] = raw.replace(m.group(1) + ">", m.group(1) + "=", 1)
            print("I18N06 %s:%d %s" % (os.path.relpath(path, root), start, m.group(1)))
            changed = True
    if changed:
        write(path, lines)


def referenced(root, full):
    """True when a file of the project other than a bundle names the full key."""
    out = subprocess.run(["grep", "-rlF", "--exclude=*_messages*.properties", "--exclude-dir=target", "--exclude-dir=.git",
                          "--exclude-dir=e2e", full, root], capture_output=True, encoding="utf-8", errors="replace").stdout
    return bool(out.strip())


def asked(root, key):
    """True when a file of the project other than a bundle names the key itself (after module.<plugin>. for a module), not as the tail of a longer key."""
    rx = r"(^|[^A-Za-z0-9_.]|module[.][A-Za-z0-9_]+[.])%s([^A-Za-z0-9_.]|$)" % re.escape(key).replace("\\.", "[.]")
    out = subprocess.run(["grep", "-rlE", "--exclude=*.properties", "--exclude-dir=target", "--exclude-dir=.git",
                          "--exclude-dir=e2e", rx, root], capture_output=True, encoding="utf-8", errors="replace").stdout
    return bool(out.strip())


def strip_prefix(path, root):
    """Step 3: `<prefix>.key` becomes `key`, or goes when `key` is already there."""
    prefix = os.path.basename(path).split("_messages")[0] + "."
    known = bundles.keys(path)
    lines = read(path)
    drop = set()
    for start, end, text in bundles.spans(path):
        m = bundles.KEY.match(text)
        if not m or not m.group(1).startswith(prefix):
            continue
        key = m.group(1)
        short = key[len(prefix):]
        rel = os.path.relpath(path, root)
        if referenced(root, prefix + key) or not asked(root, key):
            continue
        if short in known:
            drop.update(range(start, end + 1))
            print("I18N01 %s:%d %s removed, %s is declared" % (rel, start, key, short))
        else:
            lines[start - 1] = lines[start - 1].replace(key, short, 1)
            known.add(short)
            print("I18N01 %s:%d %s -> %s" % (rel, start, key, short))
    new = [ln for i, ln in enumerate(lines, 1) if i not in drop]
    if new != read(path):
        write(path, new)


def drop_duplicates(path, root):
    """Step 4: every occurrence of a key but the last one is removed."""
    spans = list(bundles.spans(path))
    last = {}
    for start, _, text in spans:
        m = bundles.KEY.match(text)
        if m:
            last[m.group(1)] = start
    drop = set()
    for start, end, text in spans:
        m = bundles.KEY.match(text)
        if m and last[m.group(1)] != start:
            drop.update(range(start, end + 1))
            print("I18N10 %s:%d %s removed, redeclared line %d" % (os.path.relpath(path, root), start, m.group(1)[:60],
                                                                   last[m.group(1)]))
    if drop:
        write(path, [ln for i, ln in enumerate(read(path), 1) if i not in drop])


def drop_keys(path, root, dead):
    """Removes the listed dead keys from a bundle."""
    lines = read(path)
    drop = set()
    for start, end, text in bundles.spans(path):
        m = bundles.KEY.match(text)
        if m and m.group(1) in dead:
            drop.update(range(start, end + 1))
            print("I18N08 %s:%d %s removed" % (os.path.relpath(path, root), start, m.group(1)[:60]))
    if drop:
        write(path, [ln for i, ln in enumerate(lines, 1) if i not in drop])


def drop_orphans(path, default, root):
    """Step 5: a translation key the default bundle does not declare is removed."""
    ref = bundles.keys(default)
    lines = read(path)
    drop = set()
    for start, end, text in bundles.spans(path):
        m = bundles.KEY.match(text)
        if m and m.group(1) not in ref:
            drop.update(range(start, end + 1))
            print("I18N09 %s:%d %s removed, not in %s" % (os.path.relpath(path, root), start, m.group(1)[:60],
                                                           os.path.basename(default)))
    if drop:
        write(path, [ln for i, ln in enumerate(lines, 1) if i not in drop])


def escape(value):
    """A properties value: non-ASCII characters as \\uXXXX, line breaks as \\n."""
    return "".join(c if 32 <= ord(c) < 127 else "\\n" if c == "\n" else "\\u%04x" % ord(c) for c in value)


def add_keys(root, entries):
    """Sets each (bundle file name, key, value) in the bundle of that name, appending the keys it does not declare."""
    files = {os.path.basename(f): f for f in glob.glob(os.path.join(root, "src/java/**/*_messages*.properties"), recursive=True)}
    for name, key, value in entries:
        path = files.get(name)
        if not path:
            print("ADD %s: no bundle %s in the project" % (key, name))
            continue
        lines = read(path)
        eol = "\r\n" if any(ln.endswith("\r\n") for ln in lines) else "\n"
        line = "%s=%s%s" % (key, escape(value), eol)
        span = [(s, e) for s, e, text in bundles.spans(path) if bundles.KEY.match(text) and bundles.KEY.match(text).group(1) == key]
        if span:
            s, e = span[-1]
            lines[s - 1:e] = [line]
        else:
            if lines and not lines[-1].endswith(("\n", "\r")):
                lines[-1] += eol
            lines.append(line)
        write(path, lines)
        print("%s %s:%s" % ("SET" if span else "ADD", os.path.relpath(path, root), key))


def repair(root, dead):
    """Runs the five steps on every bundle of the project, each step on what the previous one wrote."""
    rename_country_bundles(root)
    files = sorted(glob.glob(os.path.join(root, "src/java/**/*_messages*.properties"), recursive=True))
    for path in files:
        fix_arrows(path, root)
        strip_prefix(path, root)
        drop_duplicates(path, root)
        if dead:
            drop_keys(path, root, dead)
    for default in sorted(glob.glob(os.path.join(root, "src/java/**/*_messages.properties"), recursive=True)):
        for path in sorted(glob.glob(default[:-len(".properties")] + "_*.properties")):
            drop_orphans(path, default, root)


def main():
    """Repairs the project in place, or, with --dry-run, a copy of it: the printed changes are the ones a real run makes."""
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dead = set()
    if "--drop" in args:
        i = args.index("--drop")
        dead = {k.strip() for k in open(args[i + 1], encoding="utf-8", errors="replace") if k.strip()}
        del args[i:i + 2]
    entries = []
    if "--add" in args:
        i = args.index("--add")
        for ln in open(args[i + 1], encoding="utf-8", errors="replace"):
            m = re.match(r"\s*([A-Za-z0-9_.-]+?)(_[a-z]{2})?:([^=\s]+)=(.*?)\r?\n?$", ln)
            if m:
                entries.append(("%s_messages%s.properties" % (m.group(1), m.group(2) or ""), m.group(3), m.group(4)))
        del args[i:i + 2]
    root = os.path.abspath(args[0] if args else ".")
    if "--dry-run" not in sys.argv:
        add_keys(root, entries)
        repair(root, dead)
        return
    with tempfile.TemporaryDirectory() as tmp:
        copy = os.path.join(tmp, os.path.basename(root))
        shutil.copytree(root, copy, symlinks=True, ignore=shutil.ignore_patterns("target", ".git", "e2e", "node_modules"))
        add_keys(copy, entries)
        repair(copy, dead)


if __name__ == "__main__":
    main()
