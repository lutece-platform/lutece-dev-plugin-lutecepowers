#!/usr/bin/env python3
"""template_rules.py — house rules on Lutece 8 templates that block a migration.

Usage: template_rules.py <rule> [project_root | template_file]
       rule: offcanvas | fo-forms | inline-forms | jquery | fo-upload | unsafe-messages | suggestpoi | fo-required-js
             | mvc-message | own-messages

Prints one line per breach, `path:line: excerpt`, and exits 1 when there is one. FreeMarker, HTML, JSP and script
comments are ignored, and so are the macro libraries under templates/*/themes/. Shared by verify-migration.sh (TM02
to TM07, TM10 to TM12) and scan-template-design.py (TD48, TD49, TD50).

- offcanvas     no @offcanvas / @cOffcanvas / offcanvas markup: the content of the page goes in a @modal (@cModal),
                another page is reached by a plain link.
- fo-forms      every front-office form is a @cForm, which loads the core's theme-form-validation; a raw <form>, a
                back-office @tform in a skin template, or foValidation=false leaves the form without it. A standalone
                page (an <html> root, outside the site frameset) is not checked.
- inline-forms  no form laying three visible fields or more side by side on one line: @tform type inline/flex,
                form-inline / d-flex / d-inline-flex on the form, two @formGroup formStyle='inline' or more, or a
                @row with three columns or more that each carry a text-like field. Two columns (fields and an image,
                first and last name) are fine; a grid of checkboxes or switches is allowed.
- jquery        a jQuery call in a template or a script under the templates (the plugin's other scripts are read by
                verify-migration.sh).
- fo-upload     a back-office template calling the front-office upload macros (addFileInput, addUploadedFilesBox,
                addFileInputAndfilesBox) instead of the BO ones.
- unsafe-messages  errors, infos or warnings read with ?size / ?has_content without a default: the MVC model holds
                them only when there is one.
- suggestpoi    the old jQuery SuggestPOI autocomplete (autocomplete-js.jsp, createAutocomplete, .autocomplete( ),
                also in the JSPs.
- fo-required-js  @addRequiredJsFiles in a back-office template instead of @addRequiredBOJsFiles.
- mvc-message   ${x} where x is the loop variable of a list over errors (an MVCMessage, printed through ${x.message}),
                or ${x.message} over infos or warnings (strings: the page throws), unless the body tests it or the
                project fills that list with MVCMessage objects itself.
- own-messages  ${x.message} over infos or warnings the project fills with MVCMessage objects itself: it works, the
                modern form is the core's addInfo( ) / addWarning( ) and ${x}.
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


def blank_scripts(text):
    """Blank JSP comments, /* */ comments and // comments that do not follow a colon or a quote, keeping offsets."""
    def blank(match):
        return re.sub(r"[^\n]", " ", match.group(0))
    text = re.sub(r"<%--.*?--%>", blank, text, flags=re.S)
    text = re.sub(r"/\*.*?\*/", blank, text, flags=re.S)
    return re.sub(r"(?<![:\"'\\\w])//[^\n]*", blank, text)


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


JQUERY = re.compile(r"\bjQuery\b|\$\(")
FO_UPLOAD = re.compile(r"<@(addFileInput|addUploadedFilesBox|addFileInputAndfilesBox)(?=[\s/>])")
UNSAFE_MESSAGES = re.compile(r"(?<![\w.!)])(errors|infos|warnings)\?(size|has_content)\b")
SUGGESTPOI = re.compile(r"autocomplete-js\.jsp|\bcreateAutocomplete\b|\.autocomplete\(")
FO_REQUIRED_JS = re.compile(r"<@addRequiredJsFiles(?=[\s/>])")
MESSAGE_LIST = re.compile(r"<#list\s+\(?(errors|infos|warnings)(?:!(?:\[\s*\])?)?\)?\s+as\s+(\w+)\s*>")
LIST_TAG = re.compile(r"<#list\b|</#list\s*>")


def jquery(text, skin):
    """Lines of the jQuery calls."""
    return [line_of(text, m.start()) for m in JQUERY.finditer(text)]


def fo_upload(text, skin):
    """Lines of the front-office upload macros called from a back-office template."""
    return [] if skin else [line_of(text, m.start()) for m in FO_UPLOAD.finditer(text)]


def unsafe_messages(text, skin):
    """Lines reading errors, infos or warnings with ?size / ?has_content and no default nor ?? guard on the line."""
    out = []
    for m in UNSAFE_MESSAGES.finditer(text):
        start = text.rfind("\n", 0, m.start()) + 1
        if not re.search(r"\b%s\?\?" % m.group(1), text[start:m.start()]):
            out.append(line_of(text, m.start()))
    return out


def suggestpoi(text, skin):
    """Lines of the old SuggestPOI autocomplete."""
    return [line_of(text, m.start()) for m in SUGGESTPOI.finditer(text)]


def fo_required_js(text, skin):
    """Lines of @addRequiredJsFiles in a back-office template."""
    return [] if skin else [line_of(text, m.start()) for m in FO_REQUIRED_JS.finditer(text)]


OWN_MESSAGE_LISTS = set()
ADMIN_BASES = {"MVCAdminJspBean", "PluginAdminPageJspBean", "AdminFeaturesPageJspBean"}
COMMENTS = re.compile(r"/\*.*?\*/|//[^\n]*", re.S)


def own_message_lists(root):
    """(list, side) pairs the project fills with MVCMessage objects itself: a main Java class (comments aside) that
    creates an MVCMessage and names the list (MARK_INFOS, "infos"); its side is skin for an MVCApplication, admin for
    an admin JspBean. Only that side's templates may print ${x.message} over that list."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import java_checks
    files = java_checks.sources(root)
    info = java_checks.types(files)
    found = set()
    for cls, i in info.items():
        code = COMMENTS.sub("", files[i["path"]])
        if not re.search(r"\bnew\s+MVCMessage\s*\(", code):
            continue
        seen, stack = set(), [cls]
        while stack:
            t = stack.pop()
            if t not in seen:
                seen.add(t)
                stack.extend(info.get(t, {}).get("supers", []))
        sides = ({"skin"} if "MVCApplication" in seen else set()) | ({"admin"} if seen & ADMIN_BASES else set())
        for kind in ("infos", "warnings"):
            if re.search(r"\bMARK_%s\b|\"%s\"" % (kind.upper(), kind), code):
                found |= {(kind, side) for side in sides}
    return found


def project_root(path):
    """The nearest folder holding a pom.xml at or above a path, else the path's folder."""
    at = os.path.abspath(path if os.path.isdir(path) else os.path.dirname(path))
    while at != os.path.dirname(at):
        if os.path.isfile(os.path.join(at, "pom.xml")):
            return at
        at = os.path.dirname(at)
    return os.path.abspath(path if os.path.isdir(path) else os.path.dirname(path))


def message_prints(text):
    """(line, list) of each loop variable printed the wrong way for the core's lists: a list over errors without
    .message, a list over infos or warnings with .message unless the body tests it (x.message??, ?is_string)."""
    out = []
    for m in MESSAGE_LIST.finditer(text):
        depth, end = 1, len(text)
        for tag in LIST_TAG.finditer(text, m.end()):
            depth += -1 if tag.group(0).startswith("</") else 1
            if depth == 0:
                end = tag.start()
                break
        body, var = text[m.end():end], re.escape(m.group(2))
        if m.group(1) == "errors":
            wrong = r"\$\{\s*%s\s*\}" % var
        elif re.search(r"\b%s\.message\?\?|\b%s\?is_string" % (var, var), body):
            continue
        else:
            wrong = r"\$\{\s*%s\.message\b" % var
        out += [(line_of(text, m.end() + h.start()), m.group(1)) for h in re.finditer(wrong, body)]
    return out


def mvc_message(text, skin):
    """Lines printing a message the way that throws or shows the object (TM07), the lists this template's side fills
    with MVCMessage objects itself aside: those are own-messages (TM13)."""
    side = "skin" if skin else "admin"
    return [line for line, kind in message_prints(text) if (kind, side) not in OWN_MESSAGE_LISTS]


def own_messages(text, skin):
    """Lines printing ${x.message} over infos or warnings this template's side fills with MVCMessage objects itself:
    it works, the modern form is the core's addInfo( ) / addWarning( ) and ${x} (TM13)."""
    side = "skin" if skin else "admin"
    return [line for line, kind in message_prints(text) if (kind, side) in OWN_MESSAGE_LISTS]


RULES = {"offcanvas": offcanvas, "fo-forms": fo_forms, "inline-forms": inline_forms, "jquery": jquery, "fo-upload": fo_upload,
         "unsafe-messages": unsafe_messages, "suggestpoi": suggestpoi, "fo-required-js": fo_required_js, "mvc-message": mvc_message, "own-messages": own_messages}
SCOPES = {"jquery": (("webapp/WEB-INF/templates",), (".html", ".ftl", ".js")),
          "suggestpoi": (("webapp",), (".html", ".ftl", ".jsp"))}
DEFAULT_SCOPE = (("webapp/WEB-INF/templates/admin", "webapp/WEB-INF/templates/skin"), (".html", ".ftl"))
MACRO_LIBRARY = re.compile(r"/templates/(admin|skin)/themes/")


def main():
    """Entry point."""
    if len(sys.argv) < 2 or sys.argv[1] not in RULES:
        print(__doc__, file=sys.stderr)
        return 2
    rule = RULES[sys.argv[1]]
    subs, exts = SCOPES.get(sys.argv[1], DEFAULT_SCOPE)
    root = sys.argv[2] if len(sys.argv) > 2 else "."
    if os.path.isfile(root):
        paths, base = [root], os.path.dirname(root)
    else:
        paths, base = [], root
        for sub in subs:
            for dirpath, dirs, files in os.walk(os.path.join(root, sub)):
                dirs.sort()
                paths += [os.path.join(dirpath, n) for n in sorted(files) if n.endswith(exts)]
        paths = [p for p in paths if not MACRO_LIBRARY.search(os.path.abspath(p).replace(os.sep, "/"))]
    if sys.argv[1] in ("mvc-message", "own-messages"):
        OWN_MESSAGE_LISTS.update(own_message_lists(project_root(root)))
    found = 0
    for path in paths:
        with open(path, encoding="utf-8", errors="replace", newline="") as fh:
            raw = fh.read().replace("\r\n", "\n")
        text = blank_scripts(blank_comments(raw))
        for hit in rule(text, "/templates/skin/" in os.path.abspath(path)):
            line = hit[0] if isinstance(hit, tuple) else hit
            print("%s:%d: %s" % (os.path.relpath(path, base), line, raw.split("\n")[line - 1].strip()[:100]))
            found += 1
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
