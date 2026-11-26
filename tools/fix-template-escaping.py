#!/usr/bin/env python3
"""Rewrites in place the template findings of always-on auto-escaping that have one safe form.

- TM18  an HTML entity in a string literal becomes its character ('a?x=1&amp;y=2' -> 'a?x=1&y=2'), the literals TM18
        reports and no other. A literal whose entity stands for FreeMarker syntax ($ { } #) is left.
- TM20  #i18n{key} in a script becomes ${i18n('key')?js_string?no_esc} on lutece-core 8.1 (autoescape-target.py),
        ${i18n('key')?js_string} before. A key built with ${...} or a message inside an interpolation is left.
- TM16  a captured block TM16 reports (read as a string) becomes an expression when its body only computes text:
        text -> 'text', ${e} -> ( e )?string, <#if>/<#elseif>/<#else> -> ?then, <#list xs as x> -> ?map( x -> ... )
        ?join( '' ). A body holding markup, an entity, attributes, a comment, ?no_esc or richText, a loop variable
        built-in or another directive, a capture given as params or read with ?markup_string, is left. A capture
        nothing reads as a string works as markup and is not touched.

Every changed file is parsed with FreeMarker before and after, in the project's mode (check-template-parse.sh): a
file that parsed and no longer does keeps its content and is listed. Without a JDK or a freemarker jar the captures
are left, as the one rewrite that rebuilds directives. Prints `file:line CODE before -> after` per change and
`file:line CODE left: reason` per case left; --dry-run writes nothing.

    fix-template-escaping.py [--dry-run] <project_dir>
"""
import html
import os
import re
import subprocess
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import template_rules as rules

FTL_SYNTAX = set("${}#")
I18N_KEY = re.compile(r"[\w.]+")
CAPTURE = re.compile(r"<#(assign|local)\s+(\w+)\s*>(.*?)</#\1\s*>", re.S)
IF_OR_LIST = re.compile(r"<#(if|list)\b")
TEXT_IO = {"encoding": "utf-8", "errors": "surrogateescape", "newline": ""}
FTL_OPEN = re.compile(r"<(/?)#(\w+)")
ENTITY_TEXT = re.compile(r"&(\w+|#\d+|#x[0-9a-fA-F]+);")
STOPS = ("sep", "items", "break", "continue", "return", "assign", "local", "global", "include", "import", "nested")
LOOP_VARIABLE = r"\b%s\?(index|counter|has_next|is_last|is_first|item_)"


def short(text):
    """A one-line excerpt of a text."""
    text = re.sub(r"\s+", " ", text)
    return text if len(text) <= 80 else text[:77] + "..."


def blanked(raw):
    """The text with its comments blanked, offsets kept, as the rules read it."""
    return rules.blank_scripts(rules.blank_comments(raw))


def decoded_literal(literal):
    """The literal with its entities turned to characters (quote and backslash escaped), or None when one stands for
    FreeMarker syntax."""
    quote = literal[0]
    out, last = [], 0
    for m in rules.ENTITY.finditer(literal, 1, len(literal) - 1):
        char = html.unescape(m.group(0))
        if char == m.group(0):
            continue
        if FTL_SYNTAX & set(char):
            return None
        out += [literal[last:m.start()], "".join("\\" + c if c in (quote, "\\") else c for c in char)]
        last = m.end()
    return "".join(out) + literal[last:]


def fix_entities(raw, report):
    """The text with the TM18 literals decoded."""
    for start, end in sorted(rules.entity_literals(blanked(raw)), reverse=True):
        new = decoded_literal(raw[start:end])
        line = rules.line_of(raw, start)
        if new is None:
            report.left.append((line, "TM18", "entity standing for FreeMarker syntax in %s" % short(raw[start:end])))
            continue
        report.done.append((line, "TM18", "%s -> %s" % (short(raw[start:end]), short(new))))
        raw = raw[:start] + new + raw[end:]
    return raw


def interpolation_spans(text):
    """(start, end) of every ${...} of a text."""
    spans, i = [], text.find("${")
    while i >= 0:
        end = rules.interpolation_end(text, i)
        if end > 0:
            spans.append((i, end))
        i = text.find("${", max(end, i + 2))
    return spans


def fix_i18n(raw, report, form):
    """The text with the #i18n{key} of its scripts written as i18n('key') in form."""
    text = blanked(raw)
    spans = interpolation_spans(text)
    for start, end, key in sorted(rules.i18n_marks(text), reverse=True):
        line = rules.line_of(raw, start)
        if not I18N_KEY.fullmatch(key):
            report.left.append((line, "TM20", "key built at render time: #i18n{%s}" % key))
        elif any(a < start < b for a, b in spans):
            report.left.append((line, "TM20", "#i18n{%s} inside an interpolation" % key))
        else:
            new = form % key
            report.done.append((line, "TM20", "%s -> %s" % (raw[start:end], new)))
            raw = raw[:start] + new + raw[end:]
    return raw


def tag_end(text, i):
    """End offset of the FreeMarker tag whose name ends at i: a > inside quotes or brackets does not close it."""
    depth, quote = 0, None
    while i < len(text):
        c = text[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == ">" and depth <= 0:
            return i + 1
        i += 1
    return -1


def ftl_tags(text, start=0):
    """(start, end, closing, name, header) of each FreeMarker directive tag of a text from start."""
    i = start
    while True:
        m = FTL_OPEN.search(text, i)
        if not m:
            return
        end = tag_end(text, m.end())
        if end < 0:
            return
        yield m.start(), end, m.group(1) == "/", m.group(2), text[m.end():end - 1].strip().rstrip("/").strip()
        i = end


def without_tags(text):
    """The text with its directive tags removed."""
    out, last = [], 0
    for start, end, _, _, _ in ftl_tags(text):
        out.append(text[last:start])
        last = end
    return "".join(out) + text[last:]


def block(body, i, name):
    """(end of its closing tag, [(header, content)...]) of the <#if> or <#list> at i, split on its own <#elseif> and
    <#else>; None when another directive sits at its level or it does not close."""
    tags = ftl_tags(body, i)
    _, pos, _, _, head = next(tags)
    depth, parts = 0, []
    for start, end, closing, tag, header in tags:
        if tag in ("if", "list") and not closing:
            depth += 1
        elif tag in ("if", "list"):
            if depth == 0:
                if tag != name:
                    return None
                parts.append((head, body[pos:start]))
                return end, parts
            depth -= 1
        elif depth == 0 and name == "if" and tag in ("else", "elseif"):
            parts.append((head, body[pos:start]))
            head, pos = ("else" if tag == "else" else header), end
        elif depth == 0 and tag in STOPS:
            return None
    return None


def literal(text):
    """A FreeMarker string literal holding text."""
    return "'" + text.replace("\\", "\\\\").replace("'", "\\'").replace("\r", "\\r").replace("\n", "\\n") + "'"


def if_expression(parts):
    """The ?then chain computing an <#if> split in (condition, content) parts, or None."""
    tail = parts[::-1]
    expr = "''"
    if tail[0][0] == "else":
        expr = expression(tail[0][1])
        tail = tail[1:]
    for cond, content in tail:
        value = expression(content)
        if expr is None or value is None:
            return None
        expr = "( %s )?then( %s, %s )" % (cond, value, expr)
    return expr


def list_expression(parts):
    """The ?map( )?join( '' ) computing a <#list> split in parts, or None when it reads its loop variable state."""
    m = re.fullmatch(r"(.+?)\s+as\s+(\w+)", parts[0][0], re.S)
    if not m or len(parts) != 1 or re.search(LOOP_VARIABLE % m.group(2), parts[0][1]):
        return None
    value = expression(parts[0][1])
    return None if value is None else "( %s )?map( %s -> %s )?join( '' )" % (m.group(1).strip(), m.group(2), value)


def expression(body):
    """An expression computing the text of a capture body, or None when the body holds markup or a construct it does
    not translate."""
    out, i = [], 0
    while i < len(body):
        if body.startswith("${", i):
            end = rules.interpolation_end(body, i)
            if end < 0:
                return None
            e = body[i + 2:end - 1].strip()
            if re.search(r"\?no_esc\b|\brichText\s*\(", e):
                return None
            out.append("( %s )?string" % (e + "''" if e.endswith("!") else e))
            i = end
        elif directive := IF_OR_LIST.match(body, i):
            name = directive.group(1)
            found = block(body, i, name)
            if found is None:
                return None
            i, parts = found
            value = if_expression(parts) if name == "if" else list_expression(parts)
            if value is None:
                return None
            out.append(value)
        elif body[i] == "<" or ENTITY_TEXT.match(body, i):
            return None
        else:
            j = i + 1
            while j < len(body) and not body.startswith("${", j) and body[j] != "<" and not ENTITY_TEXT.match(body, j):
                j += 1
            if "#{" in body[i:j]:
                return None
            out.append(literal(body[i:j]))
            i = j
    return " + ".join(out) or "''"


def markup(text):
    """True when a capture body, its directives removed, holds an HTML tag or an entity."""
    return bool(re.search(r"</?[a-zA-Z][^>]*>", text) or ENTITY_TEXT.search(text))


def fix_captures(raw, report, params):
    """The text with the captures read as a string assigned as expressions when their body only computes text."""
    text = blanked(raw)
    read = {name for _, name in rules.capture_string_reads(text)}
    for m in reversed(list(CAPTURE.finditer(text))):
        kind, name, body = m.group(1), m.group(2), raw[m.start(3):m.end(3)]
        if name not in read:
            continue
        n = re.escape(name)
        expr, bare = None, without_tags(body)
        if body == m.group(3) and not markup(bare) and not rules.MARKUP.search(re.sub(r"\$\{[^}]*\}", "", bare)) \
                and not re.search(r"(?<![\w.])%s\?markup_string|\b(?:%s)\s*=\s*\(?\s*%s\b|<#(?:assign|local|global)\s+\w+\s*=\s*%s\s*/?>"
                                  % (n, params, n, n), text):
            expr = expression(body)
        line = rules.line_of(raw, m.start())
        if expr is None:
            report.left.append((line, "TM16", "capture read as a string, not plain text: %s" % short(raw[m.start():m.end()])))
            continue
        new = "<#%s %s = %s />" % (kind, name, expr)
        report.done.append((line, "TM16", "%s -> %s" % (short(raw[m.start():m.end()]), short(new))))
        raw = raw[:m.start()] + new + raw[m.end():]
    return raw


def parse_errors(texts, html_mode):
    """The relative paths of texts ({rel: text}) FreeMarker cannot parse, or None when no parser can run."""
    if not texts:
        return set()
    with tempfile.TemporaryDirectory() as tmp:
        for rel, text in texts.items():
            path = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", **TEXT_IO) as fh:
                fh.write(text)
        env = dict(os.environ, LP_PARSE_HTML="1" if html_mode else "0")
        out = subprocess.run(["bash", os.path.join(HERE, "check-template-parse.sh"), tmp], env=env,
                             capture_output=True, text=True).stdout
        if "FMPARSE files=" not in out:
            return None
        base = os.path.realpath(tmp)
        return {os.path.relpath(os.path.realpath(line.split(" :: ")[0][len("PARSE_ERROR "):]), base)
                for line in out.splitlines() if line.startswith("PARSE_ERROR ")}


def main():
    """Fixes the admin and skin templates of a project (core theme folders excluded)."""
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv
    root = os.path.abspath(args[0] if args else ".")
    html_mode = subprocess.run([sys.executable, os.path.join(HERE, "autoescape-target.py"), root]).returncode == 0
    form = "${i18n('%s')?js_string?no_esc}" if html_mode else "${i18n('%s')?js_string}"
    params = "|".join(sorted(map(re.escape, rules.map_params())))
    files = {}
    for path in rules.template_paths(root, "entities-in-literals"):
        rel = os.path.relpath(path, root)
        with open(path, **TEXT_IO) as fh:
            raw = fh.read()
        first, second = types.SimpleNamespace(done=[], left=[]), types.SimpleNamespace(done=[], left=[])
        safe = fix_i18n(fix_entities(raw, first), first, form)
        full = fix_captures(safe, second, params)
        if full != raw or first.left or second.left:
            files[rel] = (raw, safe, full, first, second)
    after = parse_errors({rel: full for rel, (raw, _, full, _, _) in files.items() if full != raw}, html_mode)
    before = parse_errors({rel: files[rel][0] for rel in after}, html_mode) if after else set()
    for rel, (raw, safe, full, first, second) in sorted(files.items()):
        new, done, left = full, first.done + second.done, first.left + second.left
        if after is None:
            new, done = safe, first.done
            left += [(l, c, "no FreeMarker parser (JDK, freemarker jar): capture left") for l, c, _ in second.done]
        elif rel in after and rel not in before:
            left += [(l, c, "the file no longer parses after: %s" % d) for l, c, d in done]
            new, done = raw, []
        for l, c, d in sorted(done, key=lambda x: x[0]):
            print("%s:%d %s %s" % (rel, l, c, d))
        for l, c, d in sorted(left, key=lambda x: x[0]):
            print("%s:%d %s left: %s" % (rel, l, c, d))
        if new != raw and not dry:
            with open(os.path.join(root, rel), "w", **TEXT_IO) as fh:
                fh.write(new)


if __name__ == "__main__":
    main()
