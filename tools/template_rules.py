#!/usr/bin/env python3
"""template_rules.py — house rules on Lutece 8 templates that block a migration.

Usage: template_rules.py <rule> [project_root | template_file]
       rule: offcanvas | fo-forms | inline-forms | jquery | fo-upload | unsafe-messages | suggestpoi | fo-required-js
             | mvc-message | own-messages | params-string | params-refused | capture-as-string | macro-shadow
             | entities-in-literals | html-escaped | i18n-in-scripts | url-from-data

Prints one line per breach, `path:line: excerpt`, and exits 1 when there is one. FreeMarker, HTML, JSP and script
comments are ignored, and so are the macro libraries under templates/*/themes/ (only the core's for the rules
reading project macros: params-*, capture-as-string, macro-shadow, entities-in-literals, html-escaped, i18n-in-scripts,
url-from-data). Shared by verify-migration.sh (TM02 to TM07, TM10 to TM12, TM14 to TM21), scan-template-design.py (TD48,
TD49, TD50) and fix-template-escaping.py.

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
- params-string a params argument of a macro call (params, titleParams, additionalParameters...: the parameters the
                core macros hand to htmlAttributes, read from the core of the references, and those the project's macros
                forward to them) given as a non-empty string literal, a captured block, a variable assigned a string or a
                ternary choosing strings: htmlAttributes takes a map ({'aria-label': label}) or '', anything else fails
                the rendering. A variable assigned a map literal ({...}) is a map.
- params-refused a key of a params map htmlAttributes refuses: class (the class parameter of the macro), style, an
                event handler, a URL (href, src, action, formaction) or any name out of its allow list, read from
                the core of the references (HtmlAttributesMethod).
- capture-as-string a captured block (<#assign x>...</#assign>, <#local x>) read as a string: a string built-in
                (?trim, ?length, ?replace...), a comparison with a string, or default_value=x of a select. Under
                auto-escaping a capture is markup: the page fails at render time.
- macro-shadow  a macro of the project with a parameter named like a macro it calls (icon=... and <@icon>): inside the
                body the parameter hides the macro, the call fails at render time.
- entities-in-literals an HTML entity (&amp;, &nbsp;, &#8722;) in a string literal of a directive, a macro call or
                an interpolation: auto-escaping escapes it once more. A markup fragment (a tag, attributes written as
                text: TM14) and an argument of a built-in searching a text are left alone.
- html-escaped  ${o.p} where the property p of an object is named as HTML (htmlContent, htmlSubscription...), directly
                or through a variable assigned from one: a getter returns a string, auto-escaping prints the tags as
                text. Rich text goes through ${richText(x)}.
- i18n-in-scripts #i18n{key} in a JavaScript <script> element, outside <#noparse> and the string arguments of a
                directive or a macro call: it is replaced after the rendering, as is, so an apostrophe of a translation
                ends the JavaScript string. i18n('key') is evaluated by the template and takes ?js_string.
- url-from-data an interpolation starting a URL attribute value of a raw HTML element (href, src, action, formaction,
                data, poster, background, cite, srcset, xlink:href) or a CSS url( ), reading data: a datastore key
                (dskey) or a property of an object, not wrapped in safeUrl( ) / cssUrl( ). A top-level model value or
                macro parameter (${url}, ${base_url}), a path (theme.pathCss), a paginator link, an image as base64
                and a value ending in a built-in that cannot form a scheme (?url, ?c) are left alone.
"""
import bisect
import functools
import glob
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


def spaces(text):
    """The text with every character but the line breaks turned to a space."""
    return re.sub(r"[^\n]", " ", text)


def blank(match):
    """The text of a match turned to spaces, line breaks kept."""
    return spaces(match.group(0))


def blank_comments(text):
    """Blank FreeMarker and HTML comments, keeping offsets and line numbers."""
    text = re.sub(r"<#--.*?-->", blank, text, flags=re.S)
    return re.sub(r"<!--.*?-->", blank, text, flags=re.S)


def blank_scripts(text):
    """Blank JSP comments, /* */ comments and // comments that do not follow a colon or a quote, keeping offsets."""
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


QUOTED = r"""'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*\""""
THEN_STRING = r"""\?then\(\s*['"]"""
MACRO_CALL = re.compile(r"""<@[\w.]+\b(?:%s|[^>'"])*>""" % QUOTED, re.S)
DIRECTIVE_TAG = r"""<[#@](?:%s|[^>'"])*>""" % QUOTED
TAG = re.compile(DIRECTIVE_TAG + r"""|\$\{(?:%s|[^}'"])*\}""" % QUOTED, re.S)
LITERAL = re.compile(QUOTED, re.S)
PARAMS_ARG = re.compile(r"""\b(\w+)\s*=\s*(?:(%s)|(\{)|([A-Za-z_]\w*))""" % QUOTED)
EMPTY_LITERAL = ("''", '""')
CAPTURE = re.compile(r"<#(?:assign|local)\s+(\w+)\s*>")
STRING_TERNARY = re.compile(r"(?:\.\w+|\?\w+)*" + THEN_STRING)
STRING_ASSIGN = re.compile(r"""<#(?:assign|local)\s+(\w+)\s*=(?!\s*\{)(?!\s*(?:''|"")\s*/?>)\s*(?:'|"|[^>]*%s)""" % THEN_STRING)
MAP_DEFAULT = re.compile(r"(?i)\b(\w*params\w*|additionalParameters)\s*=\s*\{\s*\}")
FORWARD = re.compile(r"\b(\w+)\s*=\s*\(?\s*(\w+)\b(?![?.(])")
MAP_PARAMS_FALLBACK = {"params", "macroParams", "titleParams", "labelParams", "legendParams", "fieldsetParams", "headerParams",
                       "actionParams", "anchorsParams", "paramsIncrease", "paramsDecrease", "additionalParameters"}
ENTITY = re.compile(r"&(#\d+|#x[0-9a-fA-F]+|[a-zA-Z]+);")
MARKUP = re.compile(r"<[#@/a-zA-Z]|[\w-]\s*=\s*[\"']")
OPEN_CALL = re.compile(r"\?(\w+)\([^()]*$")
SEARCH_BUILTINS = {"replace", "contains", "starts_with", "ends_with", "index_of", "last_index_of", "keep_before", "keep_after",
                   "keep_before_last", "keep_after_last", "split", "matches", "remove_beginning", "remove_ending"}
STRING_BUILTIN = "trim|length|substring|starts_with|ends_with|contains|replace|split|lower_case|upper_case|cap_first|index_of|matches|left_pad|right_pad"
MACRO_DEF = re.compile(r"<#macro\s+(\w+)([^>]*)>(.*?)</#macro>", re.S)
MACRO_PARAM = re.compile(r"(?:^|\s)(\w+)\s*(?==|\s|$)")
CORE_REFERENCE = os.path.join(os.path.expanduser(os.environ.get("LUTECE_REFERENCES", "~/.lutece-references")), "lutece-core")
ALLOWED_FALLBACK = {"title", "name", "value", "id", "role", "tabindex", "hidden", "lang", "dir", "placeholder", "pattern",
                    "required", "readonly", "disabled", "multiple", "min", "max", "step", "minlength", "maxlength", "size",
                    "accept", "target", "rel", "download", "alt", "width", "height", "loading", "form", "rows", "cols",
                    "selected", "checked", "autocomplete", "autofocus", "inputmode"}


def tabler_css(themes):
    """The tabler-icons.min.css under the shared css folder of a webapp's themes, wherever the core puts it; '' when none."""
    return min(glob.glob(os.path.join(themes, "shared/css/**/tabler-icons.min.css"), recursive=True), default="")


@functools.lru_cache(maxsize=None)
def allowed_names():
    """The attribute names htmlAttributes accepts in params, read from the core of the references when it is there."""
    src = os.path.join(CORE_REFERENCE, "src/java/fr/paris/lutece/portal/service/template/HtmlAttributesMethod.java")
    names = set()
    if os.path.isfile(src):
        with open(src, encoding="utf-8") as f:
            m = re.search(r"NAMES_ALLOWED\s*=\s*Set\.of\((.*?)\);", f.read(), re.S)
        names = set(re.findall(r'"([^"]+)"', m.group(1))) if m else set()
    return names or ALLOWED_FALLBACK


def forwarded_params(texts, names):
    """The macro parameters names grows into: a params-like parameter defaulting to {}, the last argument of a call to
    htmlAttributes, or a parameter a macro forwards to an argument already in names, until nothing is added."""
    pairs = []
    for text in texts:
        for m in MACRO_DEF.finditer(text):
            header, body = m.group(2), m.group(3)
            names |= set(MAP_DEFAULT.findall(header))
            own = set(MACRO_PARAM.findall(header))
            for call in re.finditer(r"htmlAttributes\(", body):
                _, end = map_keys(body, call.end() - 1)
                last = re.search(r"([A-Za-z_]\w*)\s*$", body[call.end():end])
                names |= {last.group(1)} & own if last else set()
            pairs += [(f.group(1), f.group(2)) for f in FORWARD.finditer(body) if f.group(2) in own]
    grown = True
    while grown:
        size = len(names)
        names |= {dst for src, dst in pairs if src in names}
        grown = len(names) > size
    return names


@functools.lru_cache(maxsize=None)
def map_params():
    """The macro parameters lutece-core hands to htmlAttributes as a map (params, titleParams, additionalParameters...),
    read from the core macros of the references when they are there."""
    base = os.path.join(CORE_REFERENCE, "webapp/WEB-INF/templates")
    texts = []
    for pattern in ("*.html", "*.ftl", "admin/themes/**/*.ftl", "skin/themes/**/*.ftl"):
        for path in glob.glob(os.path.join(base, pattern), recursive=True):
            with open(path, encoding="utf-8", errors="replace") as f:
                texts.append(blank_comments(f.read()))
    names = forwarded_params(texts, set())
    return frozenset(names) if "params" in names else frozenset(MAP_PARAMS_FALLBACK)


def params_args(text):
    """The params arguments of the macro calls, the core's and those the macros of text forward to them: (offset in
    text, match of PARAMS_ARG) for each one."""
    names = forwarded_params([text], set(map_params())) if "<#macro" in text else map_params()
    for call in MACRO_CALL.finditer(text):
        for m in PARAMS_ARG.finditer(call.group(0)):
            if m.group(1) in names:
                yield call.start(), m


def params_string(text, skin):
    """Lines of the params arguments given as a non-empty string, a capture, a variable assigned one, or a ternary
    choosing between strings (cond?then('a="1"', ''))."""
    stringy = set(CAPTURE.findall(text)) | set(STRING_ASSIGN.findall(text))
    return [line_of(text, base + m.start()) for base, m in params_args(text)
            if (m.group(2) and m.group(2) not in EMPTY_LITERAL) or m.group(4) in stringy
            or (m.group(4) and STRING_TERNARY.match(text, base + m.end()))]


def entity_literals(text):
    """(start, end) of each string literal, quotes included, of a directive, a macro call or an interpolation holding
    an HTML entity; markup fragments (a tag, attributes written as text) and the arguments of a search built-in
    (?replace('&nbsp;', '')) aside."""
    for tag in TAG.finditer(text):
        body = tag.group(0)
        for lit in LITERAL.finditer(body):
            value = lit.group(0)[1:-1]
            if not ENTITY.search(value) or MARKUP.search(value):
                continue
            call = OPEN_CALL.search(body, 0, lit.start())
            if call and call.group(1) in SEARCH_BUILTINS:
                continue
            yield tag.start() + lit.start(), tag.start() + lit.end()


def entities_in_literals(text, skin):
    """Lines of the HTML entities in a string literal of a directive, a macro call or an interpolation."""
    return sorted({line_of(text, start) for start, _ in entity_literals(text)})


def map_keys(text, start):
    """The keys of the map literal opening at start, the end offset: top-level keys only, values skipped."""
    keys, depth, i, expect_key = [], 0, start, False
    while i < len(text):
        c = text[i]
        if c in "'\"":
            j = i + 1
            while j < len(text) and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            if depth == 1 and expect_key:
                keys.append(text[i + 1:j])
                expect_key = False
            i = j + 1
            continue
        if c in "{[(":
            depth += 1
            expect_key = depth == 1
        elif c in "}])":
            depth -= 1
            if depth == 0:
                return keys, i
        elif c == "," and depth == 1:
            expect_key = True
        elif c == ":" and depth == 1:
            expect_key = False
        i += 1
    return keys, i


def params_refused(text, skin):
    """Lines of the params map keys htmlAttributes refuses."""
    allowed, out = allowed_names(), []
    for base, m in params_args(text):
        if not m.group(3):
            continue
        start = base + m.end() - 1
        for key in map_keys(text, start)[0]:
            low = key.lower()
            ok = (re.fullmatch(r"aria-[a-z]+", low) or (re.fullmatch(r"data-[a-z0-9]+(-[a-z0-9]+)*", low)
                  and low not in ("data-bs-sanitize", "data-bs-allow-list")) or low in allowed)
            if not ok:
                out.append((line_of(text, start), key))
    return out


def capture_string_reads(text):
    """(offset, name) of each read of a captured block as a string: a string built-in, a comparison in a directive or an
    interpolation, default_value= of a macro call."""
    names = {n for n in CAPTURE.findall(text) if not re.search(r"<#(?:assign|local)\s+%s\s*=\s*%s\?markup_string" % (n, n), text)}
    expressions = [(m.start(), m.group(0)) for m in re.finditer(r"<#(?:if|elseif)\b[^>]*>|\$\{[^}]*\}", text)]
    expressions += [(m.start(), m.group(0).split("=", 1)[-1]) for m in re.finditer(r"<#(?:assign|local)\b[^>]*>", text)]
    for name in names:
        n = re.escape(name)
        for m in re.finditer(r"(?<![\w.])%s\?(?:%s)\b" % (n, STRING_BUILTIN), text):
            yield m.start(), name
        for m in re.finditer(r"\bdefault_value\s*=\s*%s\b" % n, text):
            yield m.start(), name
        for start, expr in expressions:
            op = "==|!=|=" if expr.startswith(("<#if", "<#elseif", "${")) else "==|!="
            if re.search(r"(?<![\w.])%s\s*(?:%s)\s*['\"]|['\"]\s*(?:==|!=)\s*%s\b" % (n, op, n), expr):
                yield start, name


def capture_as_string(text, skin):
    """Lines reading a captured block as a string (TM16)."""
    return sorted({line_of(text, start) for start, _ in capture_string_reads(text)})


HTML_NAMED = re.compile(r"\w\.(?:html(?:[A-Z_]\w*)?|[a-z]\w*Html\w*)\b(?!\s*\()")
INTERPOLATION = re.compile(r"\$\{([^}]*)\}")
DIRECTIVE = re.compile(r"<#noautoesc>.*?</#noautoesc>|" + DIRECTIVE_TAG, re.S)
TEXTAREA_OPEN = re.compile(r"<textarea\b|<@(?:input|cInput)\b[^>]*type\s*=\s*['\"]textarea['\"][^>]*(?<!/)>|<@(?:cTextarea|textarea)\b[^>]*(?<!/)>")
TEXTAREA_CLOSE = re.compile(r"</textarea\s*>|</@(?:input|cInput|cTextarea|textarea)\s*>")
SAFE_OUTPUT = re.compile(r"richText\(|\?(?:no_esc|markup_string|js_string|json_string|url|c|size|length|has_content|string\b|then)")


def html_escaped(text, skin):
    """Lines printing a value named as HTML, or a variable assigned from one, with ${...} and no richText; not in a
    textarea, an argument of a directive or a macro, or a noautoesc block."""
    tainted = {m.group(1) for m in re.finditer(r"<#(?:assign|local)\s+(\w+)\s*=([^>]*)>", text)
               if HTML_NAMED.search(m.group(2)) and not SAFE_OUTPUT.search(m.group(2))}
    skipped = [d.span() for d in DIRECTIVE.finditer(text)]
    starts = [a for a, _ in skipped]
    opens = [t.end() for t in TEXTAREA_OPEN.finditer(text)]
    closes = [t.end() for t in TEXTAREA_CLOSE.finditer(text)]
    out = []
    for m in INTERPOLATION.finditer(text):
        pos, expr = m.start(), m.group(1)
        i = bisect.bisect_left(starts, pos) - 1
        if (i >= 0 and pos < skipped[i][1]) or SAFE_OUTPUT.search(expr) \
                or bisect.bisect_right(opens, pos) > bisect.bisect_right(closes, pos):
            continue
        if HTML_NAMED.search(expr) or re.sub(r"!\s*(?:''|\"\")?\s*$", "", expr.strip()) in tainted:
            out.append(line_of(text, pos))
    return out


def macro_shadow(text, skin):
    """Lines of the macros of the project whose parameter hides a macro the body calls."""
    out = []
    for m in MACRO_DEF.finditer(text):
        names = set(MACRO_PARAM.findall(m.group(2)))
        for name in names:
            if re.search(r"<@%s\b" % re.escape(name), m.group(3)):
                out.append(line_of(text, m.start()))
    return out


NOPARSE = re.compile(r"<#noparse>.*?</#noparse>", re.S)
SCRIPT_ELEMENT = re.compile(r"(<script\b([^>]*)>)(.*?)(</script\s*>)", re.S | re.I)
SCRIPT_TYPE = re.compile(r"""\btype\s*=\s*['"]?([^'"\s>]+)""", re.I)
JS_TYPES = {"text/javascript", "application/javascript", "text/ecmascript", "application/ecmascript", "module"}
I18N_MARK = re.compile(r"#i18n\{((?:\$\{[^{}]*\}|[^{}])*)\}")
HTML_TAG = re.compile(r"""<([a-zA-Z][\w:-]*)((?:[^<>"']|"[^"]*"|'[^']*'|</?#[^>]*>|\$\{[^}]*\})*)>""")
URL_ATTR = re.compile(r"""(?<![\w:-])(?:href|src|action|formaction|data|poster|background|cite|srcset|xlink:href)\s*=\s*["']\s*(?=\$\{)""", re.I)
STYLE_ATTR = re.compile(r"""(?<![\w:-])style\s*=\s*("[^"]*"|'[^']*')""", re.I)
STYLE_ELEMENT = re.compile(r"<style\b[^>]*>(.*?)</style\s*>", re.S | re.I)
CSS_URL = re.compile(r"""url\(\s*['"]?\s*(?=\$\{)""", re.I)
URL_GUARD = re.compile(r"\b(?:safeUrl|cssUrl)\s*\(|\?(?:c|url|url_path|size|index|counter|has_content|string\.computer|iso\w*)(?:\([^()]*\))?\s*$")
REFERENCE = re.compile(r"^[\s(]*([A-Za-z_]\w*(?:\s*(?:\.\s*[A-Za-z_]\w*|\(\s*\)))*)")
SERVER_BUILT = re.compile(r"(?i)path|base64|paginator")


def interpolation_end(text, start):
    """End offset of the ${...} opening at start, braces balanced, string literals and escaped characters skipped; -1
    when unclosed."""
    depth, i, quote = 0, start + 1, None
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c == "\\":
            i += 1
        elif c in "'\"":
            quote = c
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return -1


def i18n_marks(text):
    """(start, end, key) of each #i18n{key} written in a JavaScript <script> element (no type, or a JavaScript one),
    outside <#noparse> blocks and the string arguments of a directive or a macro call."""
    text = NOPARSE.sub(blank, text)
    for script in SCRIPT_ELEMENT.finditer(text):
        kind = SCRIPT_TYPE.search(script.group(2))
        if kind and kind.group(1).lower() not in JS_TYPES:
            continue
        body = re.sub(DIRECTIVE_TAG, blank, script.group(3))
        for m in I18N_MARK.finditer(body):
            yield script.start(3) + m.start(), script.start(3) + m.end(), m.group(1)


def i18n_in_scripts(text, skin):
    """Lines of the #i18n{key} written in a script (TM20)."""
    return sorted({line_of(text, start) for start, _, _ in i18n_marks(text)})


def from_data(expr):
    """True when an interpolated URL reads data: a datastore key, or a property of an object that is no path, paginator
    link or base64 image the server builds; false when safeUrl, cssUrl or a built-in that cannot form a scheme wraps it."""
    if URL_GUARD.search(expr):
        return False
    if re.search(r"\bdskey\s*\(", expr):
        return True
    ref = REFERENCE.match(expr)
    return bool(ref) and "." in ref.group(1) and not SERVER_BUILT.search(ref.group(1))


def url_from_data(text, skin):
    """Lines of the interpolations starting a URL attribute value of a raw HTML element or a CSS url( ) with a value read
    from data and not passed through safeUrl / cssUrl (TM21); script bodies and <#noparse> blocks aside."""
    text = SCRIPT_ELEMENT.sub(lambda m: m.group(1) + spaces(m.group(3)) + m.group(4), NOPARSE.sub(blank, text))
    starts = []
    for tag in HTML_TAG.finditer(text):
        starts += [tag.start(2) + a.end() for a in URL_ATTR.finditer(tag.group(2))]
        for style in STYLE_ATTR.finditer(tag.group(2)):
            starts += [tag.start(2) + style.start(1) + u.end() for u in CSS_URL.finditer(style.group(1))]
    for style in STYLE_ELEMENT.finditer(text):
        starts += [style.start(1) + u.end() for u in CSS_URL.finditer(style.group(1))]
    out = set()
    for start in starts:
        end = interpolation_end(text, start)
        if end > 0 and from_data(text[start + 2:end - 1]):
            out.add(line_of(text, start))
    return sorted(out)


RULES = {"offcanvas": offcanvas, "fo-forms": fo_forms, "inline-forms": inline_forms, "jquery": jquery, "fo-upload": fo_upload,
         "unsafe-messages": unsafe_messages, "suggestpoi": suggestpoi, "fo-required-js": fo_required_js, "mvc-message": mvc_message, "own-messages": own_messages,
         "params-string": params_string, "params-refused": params_refused, "capture-as-string": capture_as_string,
         "macro-shadow": macro_shadow, "entities-in-literals": entities_in_literals, "html-escaped": html_escaped,
         "i18n-in-scripts": i18n_in_scripts, "url-from-data": url_from_data}
SCOPES = {"jquery": (("webapp/WEB-INF/templates",), (".html", ".ftl", ".js")),
          "suggestpoi": (("webapp",), (".html", ".ftl", ".jsp"))}
DEFAULT_SCOPE = (("webapp/WEB-INF/templates/admin", "webapp/WEB-INF/templates/skin"), (".html", ".ftl"))
MACRO_LIBRARY = re.compile(r"/templates/(admin|skin)/themes/")
CORE_MACROS = re.compile(r"/templates/(admin/themes/tabler|skin/themes/macros)/")
PROJECT_MACRO_RULES = ("params-string", "params-refused", "capture-as-string", "macro-shadow", "entities-in-literals", "html-escaped",
                       "i18n-in-scripts", "url-from-data")


def template_paths(root, name):
    """The files rule name reads under a project root, sorted, the macro libraries it leaves alone aside."""
    subs, exts = SCOPES.get(name, DEFAULT_SCOPE)
    paths = []
    for sub in subs:
        for dirpath, dirs, files in os.walk(os.path.join(root, sub)):
            dirs.sort()
            paths += [os.path.join(dirpath, n) for n in sorted(files) if n.endswith(exts)]
    library = CORE_MACROS if name in PROJECT_MACRO_RULES else MACRO_LIBRARY
    return [p for p in paths if not library.search(os.path.abspath(p).replace(os.sep, "/"))]


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
        paths, base = template_paths(root, sys.argv[1]), root
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
