#!/usr/bin/env python3
"""template_rules.py — house rules on Lutece 8 templates that block a migration.

Usage: template_rules.py <rule> [project_root | template_file]      rule: offcanvas | fo-forms | inline-forms

Prints one line per breach, `path:line: excerpt`, and exits 1 when there is one. FreeMarker and HTML comments are
ignored. Shared by verify-migration.sh (TM10, TM11, TM12) and scan-template-design.py (TD48, TD49, TD50).

- offcanvas     no @offcanvas / @cOffcanvas / offcanvas markup: the content of the page goes in a @modal (@cModal),
                another page is reached by a plain link.
- fo-forms      every front-office form is a @cForm, which loads the core's theme-form-validation; a raw <form>, a
                back-office @tform in a skin template, or foValidation=false leaves the form without it. A standalone
                page (an <html> root, outside the site frameset) is not checked.
- inline-forms  no form laying three visible fields or more side by side on one line: @tform type inline/flex,
                form-inline / d-flex / d-inline-flex on the form, two @formGroup formStyle='inline' or more, or a
                @row with three columns or more that each carry a text-like field. Two columns (fields and an image,
                first and last name) are fine; a grid of checkboxes or switches is allowed.
"""
import os
import re
import sys

FIELD = re.compile(r"<@(input|select|checkBox|radioButton|cInput|cSelect|cCheckbox|cRadio|cTextarea|cInputDate|cFormCheck)\b[^>]*>"
                   r"|<(input|select|textarea)\b[^>]*>", re.S)
NOT_A_FIELD = re.compile(r"""\btype\s*=\s*['"](hidden|submit|button|reset)['"]""")
FORM = re.compile(r"<(@tform|@cForm|form)\b([^>]*)>(.*?)</\1\s*>", re.S)
INLINE_OPEN = re.compile(r"""\btype\s*=\s*['"](inline|flex)['"]|\bclass\s*=\s*['"][^'"]*\b(form-inline|d-flex|d-inline-flex)\b""")
SIDE_BY_SIDE = 3
GRID_TOKEN = re.compile(r"<@(row|cRow|columns|cCol)\b(?:'[^']*'|\"[^\"]*\"|[^>'\"])*?(?<!/)>|</@(row|cRow|columns|cCol)\s*>")
DIV_ROW = re.compile(r"""<div\b[^>]*\bclass=['"][^'"]*\brow\b[^'"]*['"][^>]*>(.*?)</div>""", re.S)
CHOICE = re.compile(r"""<@(checkBox|radioButton|cCheckbox|cRadio|cFormCheck)\b[^>]*>|<input\b[^>]*\btype\s*=\s*['"](checkbox|radio)['"][^>]*>""", re.S)
DIV_CELL = re.compile(r"""<div\b[^>]*\bclass=['"][^'"]*\bcol(?:-[a-z0-9-]+)?\b""")
OFFCANVAS = re.compile(r"""<@c?[Oo]ffcanvas\b[^>]*>|class=["'][^"']*\boffcanvas\b|data-bs-toggle=["']offcanvas""")
FO_FORM = re.compile(r"<form\b|<@tform\b|\bfoValidation\s*=\s*false")


def blank_comments(text):
    """Blank FreeMarker and HTML comments, keeping offsets and line numbers."""
    def blank(match):
        return re.sub(r"[^\n]", " ", match.group(0))
    text = re.sub(r"<#--.*?-->", blank, text, flags=re.S)
    return re.sub(r"<!--.*?-->", blank, text, flags=re.S)


def line_of(text, index):
    """1-based line number of an offset."""
    return text.count("\n", 0, index) + 1


def visible_fields(body):
    """Number of fields a user sees and fills in a form body."""
    return sum(1 for m in FIELD.finditer(body) if not NOT_A_FIELD.search(m.group(0)))


def offcanvas(text, skin):
    """(line, remote) of each offcanvas; remote when it loads another page (targetUrl, useIframe)."""
    return [(line_of(text, m.start()), bool(re.search(r"\b(targetUrl|useIframe)\s*=", m.group(0)))) for m in OFFCANVAS.finditer(text)]


def fo_forms(text, skin):
    """Lines of the front-office forms left without the core form validation."""
    if not skin or re.search(r"<html\b", text, re.I):
        return []
    return [line_of(text, m.start()) for m in FO_FORM.finditer(text)]


def macro_rows(body):
    """(offset, direct column bodies) of every @row / @cRow of the body, nesting aware: a column of a row nested in a
    column belongs to the inner row only."""
    stack = []
    for tok in GRID_TOKEN.finditer(body):
        name = tok.group(1) or tok.group(2)
        closing = tok.group(2) is not None
        if not closing and name in ("row", "cRow"):
            stack.append({"row": True, "start": tok.start(), "cells": []})
        elif not closing:
            stack.append({"row": False, "open": tok.end(), "width": column_width(tok.group(0))})
        elif stack:
            frame = stack.pop()
            if frame["row"]:
                yield frame["start"], frame["cells"]
            elif stack and stack[-1]["row"]:
                stack[-1]["cells"].append((frame["width"], body[frame["open"]:tok.start()]))


def column_width(tag):
    """Width in twelfths a column takes on a desktop screen (md, else lg, xl, xxl, sm, xs, cols), 0 when it has none
    and shares the line with its siblings."""
    for bp in ("md", "lg", "xl", "xxl", "sm", "xs", "cols"):
        m = re.search(r"\b%s\s*=\s*['\"]?(\d+)" % bp, tag)
        if m:
            return int(m.group(1))
    return 0


def lines_of_cells(cells):
    """The cells grouped by the visual line Bootstrap puts them on: a line holds twelve twelfths."""
    lines, current, used = [], [], 0
    for width, body in cells:
        if current and width and used + width > 12:
            lines.append(current)
            current, used = [], 0
        current.append(body)
        used += width
    if current:
        lines.append(current)
    return lines


def grid_fields(body):
    """Offset in the body of the first row holding SIDE_BY_SIDE columns or more that each carry a text-like field,
    or None."""
    hits = [start for start, cells in macro_rows(body)
            if any(sum(1 for cell in line if visible_fields(CHOICE.sub("", cell)) >= 1) >= SIDE_BY_SIDE for line in lines_of_cells(cells))]
    for row in DIV_ROW.finditer(body):
        cells = DIV_CELL.split(row.group(1))[1:]
        if sum(1 for cell in cells if visible_fields(CHOICE.sub("", cell)) >= 1) >= SIDE_BY_SIDE:
            hits.append(row.start())
    return min(hits) if hits else None


def inline_forms(text, skin):
    """Lines of the forms that put SIDE_BY_SIDE visible fields or more on one line: the offending row of a grid, else
    the form itself."""
    out = []
    for m in FORM.finditer(text):
        body = m.group(3)
        inline = (INLINE_OPEN.search(m.group(2)) and "flex-column" not in m.group(2)) or len(re.findall(r"""formStyle\s*=\s*['"]inline['"]""", body)) >= 2
        row = grid_fields(body)
        if inline and visible_fields(body) >= SIDE_BY_SIDE:
            out.append(line_of(text, m.start()))
        elif row is not None:
            out.append(line_of(text, m.start(3) + row))
    return out


RULES = {"offcanvas": offcanvas, "fo-forms": fo_forms, "inline-forms": inline_forms}


def main():
    """Entry point."""
    if len(sys.argv) < 2 or sys.argv[1] not in RULES:
        print(__doc__, file=sys.stderr)
        return 2
    rule = RULES[sys.argv[1]]
    root = sys.argv[2] if len(sys.argv) > 2 else "."
    if os.path.isfile(root):
        paths, base = [root], os.path.dirname(root)
    else:
        paths, base = [], root
        for sub in ("webapp/WEB-INF/templates/admin", "webapp/WEB-INF/templates/skin"):
            for dirpath, _, files in os.walk(os.path.join(root, sub)):
                paths += [os.path.join(dirpath, n) for n in sorted(files) if n.endswith((".html", ".ftl"))]
    found = 0
    for path in paths:
        raw = open(path, encoding="utf-8", errors="replace").read()
        text = blank_comments(raw)
        for hit in rule(text, "/templates/skin/" in os.path.abspath(path)):
            line = hit[0] if isinstance(hit, tuple) else hit
            print("%s:%d: %s" % (os.path.relpath(path, base), line, raw.splitlines()[line - 1].strip()[:100]))
            found += 1
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
