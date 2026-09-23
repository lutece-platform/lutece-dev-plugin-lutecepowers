#!/usr/bin/env python3
"""Repairs the i18n bundles of a Lutece project, in place, for the defects verify-migration reports as I18N05, I18N06,
I18N01 and I18N09, in that order:

1. a bundle suffixed with a country code (`_cz`, `_dk`, `_se`...) is renamed to its language code with `git mv`
   (merged into the language bundle when both exist, the language bundle winning);
2. a `key>value` line gets its `=` back;
3. a key repeating the bundle prefix (`appointment.name` in appointment_messages) loses the prefix, or is removed when
   the bundle already declares the short key;
4. in a translation, a key the default bundle does not declare is removed: nothing asks for it, it never shows.

`--drop <file>` also removes, from every language, the keys the file lists one per line (the I18N08 keys confirmed
dead once i18n_unused.py has been run against every consumer of the bundle).

Bytes are kept as they are (latin-1 round trip), line endings too. Prints one line per change; `--dry-run` only prints.

    fix-i18n-bundles.py [--dry-run] [--drop <keys_file>] <project_dir>
"""
import glob
import os
import re
import subprocess
import sys

import bundles

COUNTRY_TO_LANGUAGE = {"cz": "cs", "dk": "da", "se": "sv", "gr": "el", "jp": "ja", "cn": "zh", "ua": "uk", "kr": "ko",
                       "ee": "et", "si": "sl", "rs": "sr", "al": "sq"}
ARROW = re.compile(r"^([^=:\s]*)>([^=:]*)$")


def read(path):
    """The physical lines of a file, line endings kept."""
    return open(path, encoding="latin-1", newline="").read().splitlines(keepends=True)


def write(path, lines, dry):
    """Writes the lines back unless dry."""
    if not dry:
        open(path, "w", encoding="latin-1", newline="").write("".join(lines))


def rename_country_bundles(root, dry):
    """Step 1: country suffixes become language suffixes."""
    for path in sorted(glob.glob(os.path.join(root, "src/java/**/*_messages_*.properties"), recursive=True)):
        m = re.match(r"(.*_messages)_([a-z]{2})\.properties$", path)
        if not m or m.group(2) not in COUNTRY_TO_LANGUAGE:
            continue
        target = "%s_%s.properties" % (m.group(1), COUNTRY_TO_LANGUAGE[m.group(2)])
        print("I18N05 %s -> %s" % (os.path.relpath(path, root), os.path.basename(target)))
        if dry:
            continue
        if os.path.exists(target):
            known = bundles.keys(target)
            extra = [ln for s, e, text in bundles.spans(path) for ln in read(path)[s - 1:e]
                     if bundles.KEY.match(text) and bundles.KEY.match(text).group(1) not in known]
            lines = read(target)
            if lines and not lines[-1].endswith(("\n", "\r")):
                lines[-1] += "\n"
            write(target, lines + extra, dry)
            subprocess.run(["git", "rm", "-q", "--", path], cwd=root, check=False)
            if os.path.exists(path):
                os.remove(path)
        elif subprocess.run(["git", "mv", "--", path, target], cwd=root, capture_output=True).returncode:
            os.rename(path, target)


def fix_arrows(path, root, dry):
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
        write(path, lines, dry)


def referenced(root, full):
    """True when a file of the project other than a bundle names the full key."""
    out = subprocess.run(["grep", "-rlF", "--exclude=*_messages*.properties", "--exclude-dir=target", "--exclude-dir=.git",
                          "--exclude-dir=e2e", full, root], capture_output=True, text=True).stdout
    return bool(out.strip())


def strip_prefix(path, root, dry):
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
        if referenced(root, prefix + key):
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
        write(path, new, dry)


def drop_keys(path, root, dead, dry):
    """Removes the listed dead keys from a bundle."""
    lines = read(path)
    drop = set()
    for start, end, text in bundles.spans(path):
        m = bundles.KEY.match(text)
        if m and m.group(1) in dead:
            drop.update(range(start, end + 1))
            print("I18N08 %s:%d %s removed" % (os.path.relpath(path, root), start, m.group(1)[:60]))
    if drop:
        write(path, [ln for i, ln in enumerate(lines, 1) if i not in drop], dry)


def drop_orphans(path, default, root, dry):
    """Step 4: a translation key the default bundle does not declare is removed."""
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
        write(path, [ln for i, ln in enumerate(lines, 1) if i not in drop], dry)


def main():
    """Runs the four steps on every bundle of the project."""
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv
    dead = set()
    if "--drop" in args:
        i = args.index("--drop")
        dead = {k.strip() for k in open(args[i + 1]) if k.strip()}
        del args[i:i + 2]
    root = os.path.abspath(args[0] if args else ".")
    rename_country_bundles(root, dry)
    files = sorted(glob.glob(os.path.join(root, "src/java/**/*_messages*.properties"), recursive=True))
    for path in files:
        fix_arrows(path, root, dry)
        strip_prefix(path, root, dry)
        if dead:
            drop_keys(path, root, dead, dry)
    for default in sorted(glob.glob(os.path.join(root, "src/java/**/*_messages.properties"), recursive=True)):
        for path in sorted(glob.glob(default[:-len(".properties")] + "_*.properties")):
            drop_orphans(path, default, root, dry)


if __name__ == "__main__":
    main()
