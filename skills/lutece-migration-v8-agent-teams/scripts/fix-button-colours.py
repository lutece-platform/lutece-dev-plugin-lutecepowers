#!/usr/bin/env python3
"""Gives the back-office buttons the scanner flags TD51 and TD56 their neutral colour, in place.

TD51: `@button`/`@aButton` with color='default' or 'secondary' (or `@button cancel=true` without a colour) renders
btn-default, which the admin CSS does not define. TD56: a cancel/back button (title labelCancel, labelBack, Annuler,
Retour) without a neutral colour looks like the main action. Both become color='light'. The calls are found with the
scanner's own parser, so exactly what it reports is changed. Prints `file:line code` per change; `--dry-run` only
prints.

    fix-button-colours.py [--dry-run] <project_dir>
"""
import glob
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("scan_template_design", os.path.join(HERE, "scan-template-design.py"))
scan = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(scan)

GREY = re.compile(r"""\bcolor\s*=\s*(['"])(btn-)?(default|secondary)\1""")
ANY_COLOR = re.compile(r"""\bcolor\s*=\s*(['"])[^'"]*\1""")
NEUTRAL = re.compile(r"""\bcolor\s*=\s*['"](light|link|outline-[a-z]+|btn-light|ghost-[a-z]+)['"]""")
BACK = re.compile(r"""\btitle\s*=\s*['"][^'"]*(labelCancel|labelBack|[Cc]ancel\}|[Bb]ack\}|Annuler|Retour)""")
SUBMIT = re.compile(r"""\btype\s*=\s*['"]submit""")


def with_light(call):
    """The call with color='light', replacing its colour or adding one before the end of the tag."""
    if ANY_COLOR.search(call):
        return ANY_COLOR.sub("color='light'", call, count=1)
    return re.sub(r"\s*(/?>)$", r" color='light' \1", call)


def fix_text(text):
    """(new text, [(offset, code)]) for one template."""
    edits = []
    for name in ("button", "aButton"):
        for offset, call in scan.macro_calls(text, name):
            code = None
            if GREY.search(call) or (name == "button" and re.search(r"\bcancel\s*=\s*true", call) and not ANY_COLOR.search(call)):
                code = "TD51"
            elif BACK.search(call) and not SUBMIT.search(call) and not NEUTRAL.search(call):
                code = "TD56"
            if code:
                edits.append((offset, call, code))
    for offset, call, _ in sorted(edits, reverse=True):
        text = text[:offset] + with_light(call) + text[offset + len(call):]
    return text, [(offset, code) for offset, _, code in sorted(edits)]


def main():
    """Fixes every back-office template of the project."""
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv
    root = os.path.abspath(args[0] if args else ".")
    for path in sorted(glob.glob(os.path.join(root, "webapp/WEB-INF/templates/admin/**/*.html"), recursive=True)):
        text = open(path, encoding="utf-8", newline="").read()
        new, changes = fix_text(text)
        for offset, code in changes:
            print("%s:%d %s" % (os.path.relpath(path, root), text.count("\n", 0, offset) + 1, code))
        if changes and not dry:
            open(path, "w", encoding="utf-8", newline="").write(new)


if __name__ == "__main__":
    main()
