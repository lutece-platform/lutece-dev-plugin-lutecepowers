#!/usr/bin/env python3
"""Writes a copy of the bench war with the artefact's new jar, its webapp files and the resources of its src/java
(bundles, which a Lutece plugin ships in WEB-INF/classes, not in its jar), for `run.sh deploy`.

Liberty expands lutece.war again at every start (autoExpand), so a jar copied into the expanded application is lost
on the restart a Java change needs; the patched war is what the restarted server expands. The bench's own war is left
as it is: its date is what tells run.sh whether the image must be rebuilt.

    patch-war.py <source war> <jar> <webapp dir or ''> <output war> [<src/java dir>]
"""
import os
import sys
import zipfile


def main():
    """Copies the source war into the output, the jar, the webapp files and the src/java resources replacing their entries."""
    source, jar, webapp, output = sys.argv[1:5]
    java = sys.argv[5] if len(sys.argv) > 5 else ""
    lib = "WEB-INF/lib/" + os.path.basename(jar)
    overlay = {lib: jar}
    if webapp and os.path.isdir(webapp):
        for root, _, files in os.walk(webapp):
            for name in files:
                path = os.path.join(root, name)
                overlay[os.path.relpath(path, webapp).replace(os.sep, "/")] = path
    if java and os.path.isdir(java):
        for root, _, files in os.walk(java):
            for name in files:
                if not name.endswith(".java"):
                    path = os.path.join(root, name)
                    overlay["WEB-INF/classes/" + os.path.relpath(path, java).replace(os.sep, "/")] = path
    with zipfile.ZipFile(source) as src, zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as out:
        for item in src.infolist():
            if item.filename not in overlay:
                out.writestr(item, src.read(item.filename))
        for entry, path in sorted(overlay.items()):
            out.write(path, entry)
    print("patch-war: %d entries replaced or added" % len(overlay))


if __name__ == "__main__":
    main()
