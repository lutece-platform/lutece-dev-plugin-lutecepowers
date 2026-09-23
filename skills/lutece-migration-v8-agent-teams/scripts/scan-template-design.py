#!/usr/bin/env python3
"""scan-template-design.py — design smells in Lutece 8 templates that are already written with macros.

Usage: scan-template-design.py [project_root] [--json] [--flat] [--warn-only] [--no-exploded]

Reads webapp/WEB-INF/templates/{admin,skin} and src/sql, classifies every template (list, form, page,
fragment, email, fo) and reports the house rules a syntactically valid template can still break.
Macro names, macro signatures and Tabler icon names are read from the **assembled webapp**
(`target/lutece`, produced by `ensure-exploded.sh`, which is the precondition of the analysis): it carries the
core, every declared dependency and the project, at the versions this project really resolves. A project that
ships both macro families (the core) is its own source. `--no-exploded` falls back on the reference clone and
must be declared in the report, because a clone can be another version of the core.
Report on stdout: human text by default, JSON with --json, one line per finding with --flat; only what was asked
for, so the output can be redirected to a file. Progress and diagnostics go to stderr. Exit code 0 when the scan
ran, 2 when it could not (the project would not assemble): a caller must tell "nothing found" from "not checked".

WARN = fix it or justify it in the report.  INFO = judgment call, decide and say why.

Back-office (templates/admin)
  TD01 WARN  entity rows with edit/delete actions rendered in a @table          -> @manageFeature
  TD02 WARN  list rendering rows over a model variable, no @empty in the file   -> empty state (INFO in a fragment)
  TD04 WARN  @checkBox without orientation='switch'
  TD05 INFO  @box whose body is only a @tform / @table / @manageFeature         -> boxed=true, no box
  TD09 WARN  raw HTML tag where a macro exists
  TD10 INFO  e-mail body template (<html> root, @portal_url@, mail-client markup), out of scope
  TD40 INFO  e-mail body carrying the @cTpl theme-override hook (a mail body is not a site page)
  TD11 INFO  @box + @tform without @pageContainer: full page or fragment?
  TD12 WARN  jQuery call and no library-theme-jquery in pom.xml: no theme loads jQuery (INFO when declared).
             Also checked in the .js files under WEB-INF/templates: AppTemplateService renders those too
  TD13 INFO  icon-only button (hideTitle=['all']) without title
  TD14 WARN  btn-<color> in class: renders two colour classes (default color='primary') -> color='<color>'
  TD15 INFO  href='javascript:...' on a button                                  -> disabled button
Front-office (templates/skin)
  TD21 WARN  back-office macro in a skin template (resolves only because admin commons are auto-included)
  TD22 WARN  raw HTML tag where a c* macro exists
  TD23 INFO  skin page without <@cTpl> (a fragment needs neither cTpl nor cContainer)
  TD24 WARN  @cBtn class starting with 'btn'                                    -> class='primary' (the macro prefixes btn btn-)
  TD25 WARN  @cCol class whose first token is a number                         -> cols='12 col-md-6'
  TD27 INFO  @cAlert with a nested body and no title=                            -> title= is the main message
  TD28 INFO  raw <a>/<ul>/<li>/<div>/<span>/<img>/<hN>/<p> in a skin template     -> cLink/chList/chItem/cBlock/cInline/cImg/cTitle/cText
  TD29 INFO  @cTitle level=1 in a plugin page                                    -> level=2 (the h1 is the frameset's)
  TD31 INFO  hand-rolled password field (toggler, generator, cProgress)          -> @cInputPassword passwordMeter=true
  TD33 INFO  page template with @cTpl but no @cContainer                         -> cTpl > cContainer > cRow > cCol
  TD34 INFO  ?exists                                                              -> ?? or ?has_content
  TD37 INFO  @cBtn label='' self-closing (empty button)
Both sides
  TD06 INFO  raw & between URL parameters in href/action                         -> &amp; (never in an @offcanvas targetUrl)
  TD07 WARN  &amp; in the targetUrl of an @offcanvas useIframe: the button copies it through a JS string, the parameter is lost
  TD26 INFO  &gt; / &lt; inside a FreeMarker condition                          -> gt / lt
  TD16 WARN  argument a macro does not declare: the core macros collect it in `deprecated...` and print an HTML warning comment
  TD41 WARN  the same argument passed twice in one macro call: FreeMarker keeps the last value silently
  TD42 WARN  @checkBox orientation='switch' without value: the switch branch submits an empty string, not 'on'
  TD30 WARN  macro defined nowhere in the assembled webapp (INFO only in the --no-exploded fallback)
  TD32 WARN  icon name neither in tabler-icons.min.css nor an alias of the theme icon macro (BO icon.ftl aliases 40 FontAwesome names, FO cIcon none)
  TD35 WARN  stray text '" />' between tags (broken copy-paste)
  TD36 INFO  literal words in title=/label=/home= or in a cTitle/cText/cInline body without #i18n{}
  TD43 WARN  a <script> looks up an element the template only emits under a condition: null, and the block dies
  TD44 WARN  link or form action to a jsp/ page the assembled webapp does not carry: a 404 on click
  TD48 WARN  offcanvas (@offcanvas, @cOffcanvas, class/data-bs-toggle offcanvas): content of the page -> @modal /
             @cModal, content loaded from another page (targetUrl, useIframe) -> a plain link to that page
  TD49 WARN  front-office form that is not a @cForm, or @cForm foValidation=false: no core form validation
  TD50 WARN  inline form (fields side by side): @tform type inline/flex, formStyle inline, form-inline, d-flex on a form
  TD52 WARN  FreeMarker directive written inside a quoted macro argument (class='<#if …>…</#if>'): a string literal
             interpolates ${} but not <#…>, so the directive is printed verbatim -> compute it with <#assign> first
  TD51 WARN  @button/@aButton color='default'/'secondary' (or @button cancel=true): the macro renders btn-default,
             which the assembled admin CSS does not define: an unstyled button -> color='light'
  TD47 WARN  Bootstrap 3/4 or Font Awesome class, or a data-toggle/-target/-dismiss attribute, that neither Bootstrap 5
             nor the assembled theme CSS defines: the style or the behaviour is silently lost
  TD46 WARN  a copy of jQuery or of a jQuery plugin shipped by the project (a page loading its own jquery*.js, a file
             under webapp/ named jquery*.js or defining $.fn.x)
  TD45 WARN  jQuery-era upload widget (jQuery File Upload, SWFUpload, plupload, Dropzone, uploadify), in a template or
             vendored under webapp/: the v8 upload component is plugin-asynchronousupload (Uppy, no jQuery)
  TD38 INFO  inline style= in params
  TD39 INFO  the same <#macro> defined in several templates                     -> one shared macro_<plugin>.html
SQL
  TD08 WARN  core_admin_right icon_url pointing to an image in an init/create script: adminHeader.ftl renders <i class="${iconUrl}">
             (upgrade scripts are skipped: an old one is superseded by a later one)
Not findings: ?c on ids (Lutece sets number_format 0.######), <@cTpl> before or after <#macro> (macros are hoisted).
"""
import glob
import json
import os
import re
import subprocess

import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import template_rules  # noqa: E402

ADMIN = "webapp/WEB-INF/templates/admin"
SKIN = "webapp/WEB-INF/templates/skin"
SQL = "src/sql"
REFERENCES = os.path.expanduser("~/.lutece-references")
CORE = os.path.join(REFERENCES, "lutece-core")
BO_MACRO_DIR = os.path.join(CORE, "webapp/WEB-INF/templates/admin/themes/tabler")
FO_MACRO_DIR = os.path.join(CORE, "webapp/WEB-INF/templates/skin/themes/macros")
TABLER_CSS = os.path.join(CORE, "webapp/themes/shared/css/tabler-icons.min.css")

EMAIL_MARKERS = ("cellpadding=", "<!--[if mso", "x-apple-disable-message-reformatting", "email-container", "darkmode-bg", "@portal_url@")
INTERACTIVE = re.compile(r"<script\b|<form\b|<select\b|<input\b|<button\b", re.I)
SELF_JQUERY = re.compile(r"<script\b[^>]*\bsrc=['\"][^'\"]*jquery[-.]?(\d[\d.]*)?(\.min)?\.js", re.I)
RAW_BO_TAGS = ("option", "table", "form", "input", "select", "button", "textarea")
RAW_FO_TAGS = ("form", "input", "select", "option", "button", "table")
ROW_MARKERS = ("<@tr", "<tr", "<@manageFeatureItem", "<@li", "<li", "<@card", "<@row", "<@columns", "<@div")
ICON_ATTRS = ("buttonIcon", "btnIcon", "linkIcon", "tagIcon", "iconName", "actionIcon", "tabIcon", "iconTitle")
ACTION_ICONS = r"(buttonIcon|btnIcon)='(edit|pencil|trash)'"
RAW_AMP = r"(href|action)='[^']*\?[^']*&(?!amp;|#)[a-z_]+="
IFRAME_AMP = r"<@offcanvas\b[^>]*useIframe=true[^>]*targetUrl='[^']*&amp;|<@offcanvas\b[^>]*targetUrl='[^']*&amp;[^>]*useIframe=true"
CALL = re.compile(r"<@([A-Za-z_][A-Za-z0-9_.]*)((?:'[^']*'|\"[^\"]*\"|[^>'\"])*)/?>", re.S)
MACRO_DEF = re.compile(r"<#macro\s+([A-Za-z_][A-Za-z0-9_]*)((?:'[^']*'|\"[^\"]*\"|[^>'\"])*)>", re.S)


def read(path):
    """Return the file content, decoded leniently."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def line_of(text, index):
    """Return the 1-based line number of a character offset."""
    return text.count("\n", 0, index) + 1


def strip_comments(text):
    """Blank FreeMarker and HTML comments while keeping offsets and line numbers."""
    def blank(match):
        return re.sub(r"[^\n]", " ", match.group(0))
    text = re.sub(r"<#--.*?-->", blank, text, flags=re.S)
    return re.sub(r"<!--.*?-->", blank, text, flags=re.S)


def block_depth(text, index):
    """How many <#if> or <#list> blocks are open at an offset: what conditions an element's presence in the output."""
    opened = len(re.findall(r"<#(?:if|list)\b", text[:index]))
    closed = len(re.findall(r"</#(?:if|list)>", text[:index]))
    return opened - closed


def conditional_selectors(text):
    """Selectors a <script> looks up unconditionally while the template only emits their element under a condition.

    The lookup then returns null and the whole script block dies on the first property access, taking with it every
    behaviour it wired. Returns (selector, line of the lookup)."""
    hits = []
    for script in re.finditer(r"<script\b[^>]*>(.*?)</script>", text, flags=re.S):
        body = script.group(1)
        script_depth = block_depth(text, script.start())
        for use in re.finditer(r"""(?:(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*)?document\.(?:querySelector|getElementById)\s*\(\s*['"]#?([A-Za-z_][\w-]*)['"]""", body):
            variable, name = use.group(1), use.group(2)
            if variable and re.search(r"\b%s\s*(?:!==?\s*null|\?\.|&&)|if\s*\(\s*!?\s*%s\s*\)" % (re.escape(variable), re.escape(variable)), body):
                continue
            emitted = [m.start() for m in re.finditer(r"""\bid=['"]%s['"]""" % re.escape(name), text)]
            if not emitted:
                continue
            if all(block_depth(text, offset) > script_depth for offset in emitted):
                hits.append((name, line_of(text, script.start() + use.start())))
    return hits


def strip_scripts(text):
    """Blank <script> blocks while keeping offsets, so HTML inside JavaScript strings does not count."""
    return re.sub(r"<script\b.*?</script>", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)


def strip_markup(text):
    """Blank the FreeMarker constructs, then the HTML tags they were hiding, keeping offsets: what is left is
    the text content, where a stray quote and slash would be visible to the reader."""
    blank = lambda m: re.sub(r"[^\n]", " ", m.group(0))
    for pattern in (r"<[#@/][^<>]*>", r"<[^<>]*>"):
        while True:
            stripped = re.sub(pattern, blank, text)
            if stripped == text:
                break
            text = stripped
    return text


def strip_strings(text):
    """Replace quoted strings by empty quotes so that separators inside them do not count."""
    return re.sub(r"'[^']*'|\"[^\"]*\"", "''", text)


def signature_params(raw):
    """Parameter names of a <#macro> signature; None means the macro takes any argument (a catch-all
    other than the core's `deprecated...`, which only collects wrong arguments to print a warning comment)."""
    catch_all = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\.\.\.", raw)
    if catch_all and catch_all.group(1) != "deprecated":
        return None
    cleaned = strip_strings(raw.replace("...", ""))
    cleaned = re.sub(r"\[[^\]]*\]|\([^)]*\)|\{[^}]*\}", "", cleaned)
    names = set()
    for token in cleaned.split():
        name = token.split("=")[0].strip()
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name) and name != "deprecated":
            names.add(name)
    return names


def call_args(raw):
    """Named arguments of a macro call, and whether positional arguments were seen."""
    cleaned = strip_strings(raw)
    names = set(re.findall(r"(?<![=!<>A-Za-z0-9_.(])([A-Za-z_][A-Za-z0-9_]*)=(?!=)", cleaned))
    positional = bool(re.search(r"^\s*(''|[0-9]|[A-Za-z_][A-Za-z0-9_.]*\s*(?:/?>|$|\s+[A-Za-z_]))", cleaned)) and not names and cleaned.strip() not in ("", "/")
    return names, positional


def repeated_args(raw):
    """Named arguments a macro call passes more than once. FreeMarker accepts the call and keeps the last value,
    so neither the parse nor the render reports it."""
    listed = re.findall(r"(?<![=!<>A-Za-z0-9_.(])([A-Za-z_][A-Za-z0-9_]*)=(?!=)", strip_strings(raw))
    return sorted({name for name in listed if listed.count(name) > 1})


def switch_always_writes_value(path):
    """Whether the checkBox macro writes a value attribute in its switch branch whatever the caller passed. The
    browser then submits an empty string where a checkbox normally submits 'on', and a server reading the
    parameter with isNotEmpty sees the box as unchecked."""
    text = read(path)
    if "orientation!='switch'" not in text:
        return False
    for tag in [line for line in text.rsplit("<#else>", 1)[-1].splitlines() if "<input" in line]:
        return 'value="' in tag and not re.search(r"<#if\s+value\s*!=\s*''>\s*value=", tag)
    return False


def collect_macros(directory):
    """Map macro name -> parameter set (None = any) for every <#macro> under a directory; homonyms merge their parameters."""
    found = {}
    for path in glob.glob(os.path.join(directory, "**", "*.*"), recursive=True):
        if not path.endswith((".ftl", ".html")):
            continue
        for match in MACRO_DEF.finditer(read(path)):
            name, params = match.group(1), signature_params(match.group(2))
            if name not in found:
                found[name] = params
            elif found[name] is not None:
                found[name] = None if params is None else found[name] | params
    return found


def icon_aliases(path):
    """Legacy icon names a theme's icon macro translates to Tabler (the <#case 'name'> branches of its switch)."""
    return set(re.findall(r"<#case\s+'([a-z0-9-]+)'", read(path))) if os.path.isfile(path) else set()


def jsp_to_template(jsp):
    """CreateFaq.jsp -> create_faq: the template name a JSP conventionally renders."""
    stem = os.path.basename(jsp).rsplit(".", 1)[0]
    return re.sub(r"(?<!^)(?=[A-Z])", "_", stem).lower()


def uncloned_dependencies(root):
    """Artifact ids of the plugin/module/library dependencies of pom.xml that have no clone under the
    references: a macro they provide cannot be found, so an "undefined macro" finding would be a guess."""
    pom = os.path.join(root, "pom.xml")
    if not os.path.isfile(pom):
        return []
    declared = set(re.findall(r"<artifactId>((?:plugin|module|library)-[A-Za-z0-9._-]+)</artifactId>", read(pom)))
    clones = {os.path.basename(d) for d in glob.glob(os.path.join(REFERENCES, "*"))}
    missing = []
    for artifact in sorted(declared):
        stem = re.sub(r"^(plugin|module|library)-", "", artifact)
        if not any(stem in name for name in clones):
            missing.append(artifact)
    return missing


class Knowledge:
    """What the core and the reference plugins define: macros, signatures, icon names. When the scanned
    project is the core itself, its own theme is the truth, not the reference clone."""

    def __init__(self, root):
        global BO_MACRO_DIR, FO_MACRO_DIR, TABLER_CSS, CORE
        self.source = "reference clone"
        self.webapps = []
        templates_root = os.path.join(CORE, "webapp/WEB-INF/templates")
        # lutece:exploded writes target/lutece, lutece:exploded-lite writes target/<artifactId>-<version>
        candidates = [(d, "assembled webapp (%s)" % os.path.relpath(d, root)) for d in
                      [os.path.join(root, "target/lutece")] + sorted(glob.glob(os.path.join(root, "target", "*")))]
        candidates.append((os.path.join(root, "webapp"), "the project itself"))
        for base, label in candidates:
            bo = os.path.join(base, "WEB-INF/templates/admin/themes/tabler")
            fo = os.path.join(base, "WEB-INF/templates/skin/themes/macros")
            if os.path.isdir(bo) and os.path.isdir(fo):
                CORE, BO_MACRO_DIR, FO_MACRO_DIR, self.source = base, bo, fo, label
                self.webapps = [base, os.path.join(root, "webapp")]
                templates_root = os.path.join(base, "WEB-INF/templates")
                css = os.path.join(base, "themes/shared/css/tabler-icons.min.css")
                if os.path.isfile(css):
                    TABLER_CSS = css
                break
        self.available = os.path.isdir(BO_MACRO_DIR) and os.path.isdir(FO_MACRO_DIR)
        self.bo = collect_macros(BO_MACRO_DIR) if self.available else {}
        self.fo = collect_macros(FO_MACRO_DIR) if self.available else {}
        self.core_other = collect_macros(templates_root) if self.available else {}
        self.plugins = {}
        if self.available:
            for repo in glob.glob(os.path.join(REFERENCES, "*", "webapp/WEB-INF/templates")):
                if "/lutece-core/" in repo:
                    continue
                self.plugins.update(collect_macros(repo))
        self.local = collect_macros(os.path.join(root, "webapp/WEB-INF/templates"))
        self.uncloned = uncloned_dependencies(root)
        self.icons = set(re.findall(r"\.ti-([a-z0-9-]+):before", read(TABLER_CSS))) if os.path.isfile(TABLER_CSS) else set()
        self.bo_icons = self.icons | icon_aliases(os.path.join(BO_MACRO_DIR, "components/icon/icon.ftl"))
        self.fo_icons = self.icons | icon_aliases(os.path.join(FO_MACRO_DIR, "components/icons/cIcon.ftl"))
        self.bo_only = set(self.bo) - set(self.fo) - set(self.local)
        assembled = self.source.startswith("assembled")
        self.css_admin = theme_classes(CORE, ("/themes/skin/", "/css/skin/")) if assembled else set()
        self.css_skin = theme_classes(CORE, ("/themes/admin/", "/css/admin/")) if assembled else set()
        self.css_classes = self.css_admin | self.css_skin
        self.switch_writes_empty_value = switch_always_writes_value(os.path.join(BO_MACRO_DIR, "forms/checkbox/checkBox.ftl")) if self.available else False

    def known(self, name):
        """Whether a macro name is defined somewhere reachable."""
        return name in self.local or name in self.bo or name in self.fo or name in self.core_other or name in self.plugins

    def params(self, name):
        """Declared parameters of a macro: the local definition first, then the core, then reference plugins."""
        for table in (self.local, self.bo, self.fo, self.core_other, self.plugins):
            if name in table:
                return table[name]
        return None


def macro_calls(text, name):
    """Yield (offset, call_text) for every opening call of a macro, multi-line included."""
    for match in CALL.finditer(text):
        if match.group(1) == name:
            yield match.start(), match.group(0)


def blocks(text, name):
    """Yield (offset, body) for every <@name ...>...</@name> block."""
    for match in re.finditer(r"<@%s\b[^>]*>(.*?)</@%s>" % (re.escape(name), re.escape(name)), text, flags=re.S):
        yield match.start(), match.group(1)


def list_blocks(text):
    """Yield (offset, variable, body) for every <#list variable as x> block, nesting aware."""
    opener = re.compile(r"<#list\s+\(?([A-Za-z_][A-Za-z0-9_.]*)(!\[\])?\)?\s+as\s", re.S)
    tag = re.compile(r"<#list\b|</#list>")
    for match in opener.finditer(text):
        depth = 0
        end = None
        for inner in tag.finditer(text, match.start()):
            depth += 1 if inner.group(0).startswith("<#list") else -1
            if depth == 0:
                end = inner.start()
                break
        yield match.start(), match.group(1), text[match.end():end] if end else text[match.end():]


def looks_like_a_page(text):
    """A skin template that carries its own level 1 or 2 title is a page; anything else is a fragment another
    template includes (an entry type, a portlet body, a component), and a fragment needs neither the theme
    override hook nor the page container."""
    return bool(re.search(r"<@cTitle\b[^>]*level=[12]\b", text))


def is_email(text):
    """Tell an e-mail body template from a screen: a mail marker, or an <html> root with nothing interactive in it."""
    if any(marker in text for marker in EMAIL_MARKERS):
        return True
    return "<html" in text and not INTERACTIVE.search(text)


def classify(text, scope):
    """Guess the kind of template the reviewer will deal with."""
    if scope == "js":
        return "js"
    if scope == "sql":
        return "sql"
    if is_email(text):
        return "email"
    if re.search(r"<html\b", text, re.I):
        return "standalone"
    if scope == "skin":
        return "fo"
    if "<@pageContainer" not in text:
        return "fragment"
    if "<@manageFeature" in text or ("<@table" in text and "<#list" in text):
        return "list"
    if "<@tform" in text:
        return "form"
    return "page"


def defined_names(text):
    """Collect the names a template defines itself, so they are not mistaken for model variables."""
    names = set()
    for match in re.finditer(r"<#(?:assign|local|global)\s+([A-Za-z_][A-Za-z0-9_]*)", text):
        names.add(match.group(1))
    for match in MACRO_DEF.finditer(text):
        params = signature_params(match.group(2))
        names.update(params or set())
    for match in re.finditer(r"<#list\s+[^>]*\bas\s+([A-Za-z_][A-Za-z0-9_]*)", text):
        names.add(match.group(1))
    return names


def add(findings, code, severity, line, message):
    """Append one finding."""
    findings.append({"code": code, "severity": severity, "line": line, "message": message})


def add_grouped(findings, code, severity, hits, message):
    """Append one finding for a group of hits, with the count and the first line."""
    if hits:
        hits = sorted(hits)
        add(findings, code, severity, hits[0], "%s (%d occurrence%s)" % (message, len(hits), "s" if len(hits) > 1 else ""))


def check_jquery(text, findings, jquery_declared):
    """jQuery is not loaded by either theme unless the project declares library-theme-jquery."""
    hits = {}
    for match in re.finditer(r"(?<![A-Za-z0-9_$.])(\$\(|jQuery\(|\.ready\(|\$\.(ajax|get|post|each|extend))", text):
        hits.setdefault(line_of(text, match.start()), match.group(1))
    if not hits:
        return
    lines = sorted(hits)
    own = SELF_JQUERY.search(text)
    if own:
        add(findings, "TD46", "WARN", line_of(text, own.start()), "the page loads its own copy of jQuery%s for %d call(s): a vendored library the platform does not update (jQuery before 3.5 carries known XSS flaws); port the calls to vanilla JS and delete the copy" % (" " + own.group(1) if own.group(1) else "", len(lines)))
        return
    if UPLOAD_WIDGET.search(re.sub(r"#i18n\{[^}]*\}", "", text)):
        add(findings, "TD12", "WARN", lines[0], "jQuery call(s) in %d place(s) driving an upload widget: %s" % (len(lines), UPLOAD_ADVICE))
    elif jquery_declared:
        add(findings, "TD12", "INFO", lines[0], "jQuery call(s) in %d place(s); the project declares library-theme-jquery, so the theme loads it (adminHeader.ftl, page_frameset.html): keep it only for a widget that has no vanilla equivalent, and say so" % len(lines))
    else:
        add(findings, "TD12", "WARN", lines[0], "jQuery call(s) in %d place(s) and no library-theme-jquery dependency in pom.xml: neither theme loads jQuery, the code fails at runtime" % len(lines))


UPLOAD_WIDGET = re.compile(r"\.fileupload\(|jquery\.fileupload|jQuery-File-Upload|blueimp|SWFUpload|swfupload|plupload|new Dropzone\(|Dropzone\.options|\.uploadify\(|qq\.FineUploader")
UPLOAD_ADVICE = "the v8 upload component is plugin-asynchronousupload (Uppy, no jQuery): @addFileBOInputAndfilesBox in the back office, @addFileInputAndfilesBox in the front office, the generic AsynchronousUploadHandler injected in the bean (fileupload-patterns.md). Adding library-theme-jquery only keeps the old widget alive"


def check_upload_widget(text, findings):
    """A jQuery-era upload widget: it needs jQuery, and v8 has a component made for the job."""
    match = UPLOAD_WIDGET.search(re.sub(r"#i18n\{[^}]*\}", lambda m: " " * len(m.group(0)), text))
    if match:
        add(findings, "TD45", "WARN", line_of(text, match.start()), "upload widget '%s': %s" % (match.group(0), UPLOAD_ADVICE))


JQUERY_PLUGIN = re.compile(r"(?:\$|jQuery)\.fn\.[A-Za-z_$][\w$]*\s*=|(?:\$|jQuery)\.fn\.extend\(")


LEGACY_CLASS = re.compile(r"^(panel(-[a-z]+)?|well(-(sm|lg))?|glyphicon(-[a-z-]+)?|fa|fa-[a-z0-9-]+|btn-xs|btn-default|btn-block|col-xs-\d+|col-(xs|sm|md|lg)-(offset|push|pull)-\d+|"
                          r"label|label-(default|primary|success|info|warning|danger)|pull-(left|right)|hidden(-(xs|sm|md|lg))?|visible-(xs|sm|md|lg)(-[a-z]+)?|img-responsive|"
                          r"input-group-(addon|btn|append|prepend)|table-condensed|form-group|form-row|form-inline|custom-(select|control|checkbox|radio|switch|file|range)(-[a-z]+)?|"
                          r"sr-only(-focusable)?|badge-(primary|secondary|success|danger|warning|info|light|dark|pill)|[mp][lr]-(\d|auto|sm-\d|md-\d|lg-\d)|"
                          r"float-(left|right)|text-(left|right)|no-gutters|media(-body)?|jumbotron|card-deck|card-columns|dropdown-menu-(left|right)|"
                          r"font-weight-[a-z]+|font-italic|embed-responsive(-[a-z0-9]+)?|close)$")
LEGACY_DATA = re.compile(r"\sdata-(toggle|target|dismiss|ride|slide|slide-to|parent|spy|placement|content|original-title|backdrop|keyboard|interval|offset)\s*=")
CLASS_ATTR = re.compile(r"""\bclass\s*=\s*(["'])(.*?)\1""", re.S)


def theme_classes(base, skip):
    """Class names the CSS files of the assembled webapp define, outside the directories named in skip: a legacy name
    the theme still styles is not lost. The back office reads the admin and shared CSS, the front office the skin and
    shared CSS."""
    names = set()
    for dirpath, _, files in os.walk(base):
        if "/WEB-INF/" in dirpath + "/" or any(part in dirpath + "/" for part in skip):
            continue
        for name in files:
            if name.endswith(".css"):
                names.update(re.findall(r"\.([A-Za-z_][\w-]*)", read(os.path.join(dirpath, name))))
    return names


def check_house_forms(text, findings, kind):
    """No offcanvas, front-office forms on @cForm with the core validation, no inline form (template_rules.py)."""
    for line, remote in template_rules.offcanvas(text, kind == "fo"):
        add(findings, "TD48", "WARN", line, "offcanvas: " + ("it loads another page, link to that page instead (@aButton href, the page keeps its own back link)" if remote else "put this content in a @modal (@cModal in the front office) opened by a button with data-bs-toggle=\"modal\""))
    add_grouped(findings, "TD49", "WARN", template_rules.fo_forms(text, kind == "fo"), "front-office form without the core form validation: write it as <@cForm> (theme-form-validation loads by default), never foValidation=false")
    add_grouped(findings, "TD50", "WARN", template_rules.inline_forms(text, kind == "fo"), "inline form: two visible fields or more side by side on one line; one field per row, the standard form layout")


def check_legacy_markup(text, findings, know, kind):
    """Bootstrap 3/4 and Font Awesome markup that Bootstrap 5 and the theme ignore."""
    hits = {}
    for match in CLASS_ATTR.finditer(text):
        for token in re.split(r"\s+", re.sub(r"\$\{[^}]*\}|<#[^>]*>|</#[^>]*>", " ", match.group(2))):
            if token and LEGACY_CLASS.match(token) and token not in (know.css_skin if kind == "fo" else know.css_admin):
                hits.setdefault(token, line_of(text, match.start()))
    for match in LEGACY_DATA.finditer(text):
        hits.setdefault("data-" + match.group(1), line_of(text, match.start()))
    for token, line in sorted(hits.items(), key=lambda kv: kv[1]):
        add(findings, "TD47", "WARN", line, "'%s' is Bootstrap 3/4 or Font Awesome markup that Bootstrap 5 and the theme CSS do not define: use the v8 macro or its Bootstrap 5 / Tabler equivalent" % token)


def vendored_libraries(root):
    """(code, path) of each upload widget library or jQuery copy shipped under webapp/, outside the templates."""
    base = os.path.join(root, "webapp")
    out = []
    for dirpath, dirs, files in os.walk(base):
        if "/WEB-INF/" in dirpath + "/":
            continue
        for name in list(dirs) + files:
            if re.search(r"(?i)jquery[-.]?file[-.]?upload|swfupload|plupload|dropzone|uploadify|fine-?uploader", name):
                out.append(("TD45", os.path.relpath(os.path.join(dirpath, name), root)))
            elif re.search(r"(?i)^jquery([-.]\d[\d.]*)?(\.min)?\.js$", name):
                out.append(("TD46", os.path.relpath(os.path.join(dirpath, name), root)))
            elif name in files and name.endswith(".js") and JQUERY_PLUGIN.search(read(os.path.join(dirpath, name))):
                out.append(("TD46", os.path.relpath(os.path.join(dirpath, name), root)))
            else:
                continue
            if name in dirs:
                dirs.remove(name)
    return sorted(out)


def check_admin(text, findings, kind, opened_in_iframe, know):
    """Back-office rules on a screen template (not an e-mail body)."""
    for offset, body in blocks(text, "table"):
        rows = [m.group(0) for m in re.finditer(r"<#list\b.*?</#list>", body, flags=re.S)]
        per_row = any(len(re.findall(r"<@(aButton|button)\b", row)) >= 2 or re.search(r"<@aButton\b[^>]*href=['\"]\$\{", row) for row in rows)
        if re.search(ACTION_ICONS, body) or per_row:
            add(findings, "TD01", "WARN", line_of(text, offset), "entity rows with edit/delete actions rendered in a @table: @manageFeature is the list layout")
    if "<@empty" not in text:
        local = defined_names(text)
        hits = {}
        for offset, name, body in list_blocks(text):
            if "." in name or name in local:
                continue
            if any(marker in body for marker in ROW_MARKERS):
                hits.setdefault(name, line_of(text, offset))
        if hits:
            severity = "WARN" if kind in ("list", "page") else "INFO"
            add(findings, "TD02", severity, min(hits.values()), "rows listed from %s without an @empty state in the file%s" % (", ".join(sorted(hits)), "" if severity == "WARN" else " (fragment: decide whether an empty state belongs here)"))
    boxes = list(macro_calls(text, "checkBox"))
    switches = [(offset, call) for offset, call in boxes if "orientation='switch'" in call or 'orientation="switch"' in call]
    computed = [call for _, call in boxes if re.search(r"\borientation=(?!['\"])", call)]
    hits = [line_of(text, offset) for offset, call in boxes
            if call not in computed and "orientation='switch'" not in call and 'orientation="switch"' not in call]
    add_grouped(findings, "TD04", "WARN", hits, "@checkBox without orientation='switch'")
    if know.switch_writes_empty_value:
        hits = [line_of(text, offset) for offset, call in switches if not re.search(r"\bvalue=", call)]
        add_grouped(findings, "TD42", "WARN", hits, "@checkBox orientation='switch' without value: the switch branch writes value=\"\" whatever the caller passed, so the box submits an empty string where a checkbox submits 'on' -- give it value='1' or read the parameter with != null, never isNotEmpty")
    for match in re.finditer(r"<@boxBody\b[^>]*>\s*<@(tform|table|manageFeature)\b", text, flags=re.S):
        add(findings, "TD05", "INFO", line_of(text, match.start()), "@box holding only a @%s: drop the box (tform boxed=true; manageFeature items are cards)" % match.group(1))
    if know.css_admin and "btn-default" not in know.css_admin:
        hits = [line_of(text, offset) for name in ("button", "aButton") for offset, call in macro_calls(text, name)
                if re.search(r"""\bcolor\s*=\s*['"](btn-)?(default|secondary)['"]""", call) or (name == "button" and re.search(r"\bcancel\s*=\s*true", call) and not re.search(r"\bcolor\s*=", call))]
        add_grouped(findings, "TD51", "WARN", sorted(hits), "button colour 'default'/'secondary' (or cancel=true): the macro renders btn-default, which the admin CSS does not define, so the button has no style; use color='light'")
    no_script = strip_scripts(text)
    for tag in RAW_BO_TAGS:
        hits = [line_of(text, m.start()) for m in re.finditer(r"<%s\b" % tag, no_script)]
        add_grouped(findings, "TD09", "WARN", hits, "raw <%s> where a macro exists" % tag)
    if "<@box" in text and "<@pageContainer" not in text and "<@tform" in text:
        add(findings, "TD11", "INFO", 1, "@box + @tform without @pageContainer: a full page needs pageContainer > pageColumn > pageHeader, a fragment does not")
    hits = [line_of(text, offset) for offset, call in macro_calls(text, "aButton") if "hideTitle=['all']" in call and not re.search(r"\btitle=", call)]
    add_grouped(findings, "TD13", "INFO", hits, "icon-only @aButton without title: no label for screen readers or tooltip")
    hits = [line_of(text, m.start()) for m in re.finditer(r"<@(aButton|button)\b[^>]*class='[^']*\bbtn-(danger|primary|secondary|success|warning|info|light)\b", text, flags=re.S)]
    add_grouped(findings, "TD14", "WARN", hits, "btn-<color> in class next to the macro's default color='primary': two colour classes, CSS order decides; use color='<color>'")
    hits = [line_of(text, m.start()) for m in re.finditer(r"<@aButton\b[^>]*href='javascript:", text, flags=re.S)]
    add_grouped(findings, "TD15", "INFO", hits, "href='javascript:...' on a button: render a disabled button (href='#' color='light' class='disabled' params='aria-disabled=\"true\"')")


def check_skin(text, findings, know):
    """Front-office rules."""
    for name in sorted(know.bo_only):
        hits = [line_of(text, offset) for offset, _ in macro_calls(text, name)]
        add_grouped(findings, "TD21", "WARN", hits, "back-office macro @%s in a skin template: FO macros are the c* family (it resolves only because admin commons are auto-included)" % name)
    no_script = strip_scripts(text)
    for tag in RAW_FO_TAGS:
        hits = [line_of(text, m.start()) for m in re.finditer(r"<%s\b" % tag, no_script)]
        add_grouped(findings, "TD22", "WARN", hits, "raw <%s> where a c* macro exists" % tag)
    for tag, macro in (("a", "cLink"), ("ul", "chList"), ("li", "chItem"), ("div", "cBlock"), ("span", "cInline"), ("img", "cImg"), ("h[1-6]", "cTitle"), ("p", "cText"), ("blockquote", "cBlock type='blockquote'")):
        hits = [line_of(text, m.start()) for m in re.finditer(r"<%s\b" % tag, text)]
        add_grouped(findings, "TD28", "INFO", hits, "raw <%s> in a skin template: @%s" % (tag.replace("[1-6]", "N"), macro))
    if "<@cTpl" not in text and looks_like_a_page(text):
        add(findings, "TD23", "INFO", 1, "skin page (it carries its own level 1 or 2 title) without the <@cTpl> wrapper: a page is wrapped, a fragment included by another template is not")
    hits = [line_of(text, offset) for offset, call in macro_calls(text, "cBtn") if re.search(r"class='btn\b", call)]
    add_grouped(findings, "TD24", "WARN", hits, "@cBtn class='btn ...': the macro already writes btn btn-<class>, this renders 'btn btn-btn btn-...'; use class='primary'")
    hits = [line_of(text, offset) for offset, call in macro_calls(text, "cCol") if re.search(r"class='[0-9]", call)]
    add_grouped(findings, "TD25", "WARN", hits, "@cCol class='12 ...': the size goes in cols='12 col-md-6', class renders 'col 12 ...'")
    hits = [line_of(text, offset) for offset, call in macro_calls(text, "cTitle") if re.search(r"\blevel=1\b", call)]
    add_grouped(findings, "TD29", "INFO", hits, "@cTitle level=1 in a plugin page: the h1 belongs to the frameset, page titles start at level=2 (core and forms skin templates: 0 level=1)")
    hits = [line_of(text, m.start()) for m in re.finditer(r"password-toggler|generate_password|LutecePassword|progress_bar_first_password", text)]
    add_grouped(findings, "TD31", "INFO", hits, "hand-rolled password field (toggler, generator, cProgress, LutecePassword module): @cInputPassword passwordMeter=true pmConfirmFieldId= covers it")
    if "<@cTpl" in text and "<@cContainer" not in text and looks_like_a_page(text):
        add(findings, "TD33", "INFO", 1, "page template (it carries its own level 1 or 2 title) without @cContainer: the FO skeleton is cTpl > cContainer > cRow > cCol. A fragment is exempt, and since LUT-31677 a fragment legitimately carries @cTpl too, as its own override hook")
    hits = [line_of(text, m.start()) for m in re.finditer(r"\?exists\b", text)]
    add_grouped(findings, "TD34", "INFO", hits, "?exists is obsolete: ?? tests presence, ?has_content tests content")
    hits = [line_of(text, offset) for offset, call in macro_calls(text, "cBtn") if re.search(r"\blabel=''", call) and call.rstrip().endswith("/>")]
    add_grouped(findings, "TD37", "INFO", hits, "@cBtn label='' self-closing: an empty button, give it a label or nested content")
    hits = [line_of(text, m.start()) for m in re.finditer(r"<svg\b", text)]
    add_grouped(findings, "TD28", "INFO", hits, "raw inline <svg> in a skin template: @cIcon when a Tabler glyph fits, else cImg/img= of a macro")
    hits = [line_of(text, m.start()) for m in re.finditer(r"<@c(Title|Text|Inline)\b[^>]*>([^<{#]*[A-Za-zÀ-ÿ]{3,}[^<{#]*)</@c(Title|Text|Inline)>", text) if "#i18n" not in m.group(2) and "${" not in m.group(2)]
    add_grouped(findings, "TD36", "INFO", hits, "literal text in a @cTitle/@cText/@cInline body without #i18n{}")
    hits = [line_of(text, offset) for offset, call in macro_calls(text, "cIcon") if re.search(r"name='#i18n", call)]
    add_grouped(findings, "TD32", "WARN", hits, "@cIcon name='#i18n{...}': name is the glyph, not a label")
    hits = [line_of(text, offset) for offset, body in blocks(text, "cAlert") if body.strip() and not re.search(r"\btitle=", text[offset:offset + 400].split(">")[0])]
    add_grouped(findings, "TD27", "INFO", hits, "@cAlert with a nested body and no title=: since core 03288c4 title is the main message, the body is secondary content")


def check_common(text, findings, kind, know):
    """Rules shared by back-office and front-office templates."""
    unknown_macro = {}
    unknown_args = {}
    for match in CALL.finditer(text):
        name, raw = match.group(1), match.group(2)
        if "." in name:
            continue
        line = line_of(text, match.start())
        if know.available and not know.known(name):
            guarded = re.search(r"<#if\s+[A-Za-z_][A-Za-z0-9_.]*(\.exists|\?\?)\s*>\s*(<@[^>]*>\s*)*$", text[max(0, match.start() - 300):match.start()])
            if not guarded:
                unknown_macro.setdefault(name, line)
            continue
        params = know.params(name)
        if params is None:
            continue
        names, positional = call_args(raw)
        for arg in repeated_args(raw):
            add(findings, "TD41", "WARN", line, "@%s is passed '%s' twice: FreeMarker keeps the last value and reports nothing, neither the parse nor the render catches it" % (name, arg))
        if positional:
            continue
        for arg in sorted(names - params):
            unknown_args.setdefault((name, arg), line)
    hits = [line_of(text, m.start()) for m in CALL.finditer(text) if re.search(r"""(['"])[^'"]*<#[a-z]""", m.group(2) or "")]
    add_grouped(findings, "TD52", "WARN", hits, "FreeMarker directive inside a quoted macro argument: the string literal prints it verbatim; build the value with <#assign> before the call")
    for name, line in sorted(unknown_macro.items(), key=lambda kv: kv[1]):
        if know.source.startswith("assembled"):
            add(findings, "TD30", "WARN", line, "@%s is defined nowhere in the assembled webapp, which carries the core, every declared dependency and this project: FreeMarker fails at render" % name)
        elif know.uncloned:
            add(findings, "TD30", "INFO", line, "@%s is in no reachable source, but %s %s declared in pom.xml and not cloned under the references: assemble the project (ensure-exploded.sh) to settle it" % (name, ", ".join(know.uncloned), "is" if len(know.uncloned) == 1 else "are"))
        else:
            add(findings, "TD30", "WARN", line, "@%s is defined nowhere (core, reference plugins, this plugin) and every declared dependency is cloned: FreeMarker fails at render" % name)
    for (name, arg), line in sorted(unknown_args.items(), key=lambda kv: kv[1]):
        add(findings, "TD16", "WARN", line, "@%s does not declare '%s': the argument is dropped (deprecatedWarning comment at best)" % (name, arg))
    if know.icons:
        icons = know.fo_icons if kind == "fo" else know.bo_icons
        hits = {}
        for attr in ICON_ATTRS:
            for match in re.finditer(r"\b%s='([^'$#<{ ]+)'" % attr, text):
                if match.group(1) not in icons:
                    hits.setdefault(match.group(1), line_of(text, match.start()))
        for match in re.finditer(r"<@icon\b[^>]*\bstyle='([^'$#<{ ]+)'", text):
            if match.group(1) not in know.bo_icons:
                hits.setdefault(match.group(1), line_of(text, match.start()))
        for match in re.finditer(r"<@cIcon\b[^>]*\bname='([^'$#<{ ]+)'", text):
            if match.group(1) not in know.fo_icons:
                hits.setdefault(match.group(1), line_of(text, match.start()))
        for icon, line in sorted(hits.items(), key=lambda kv: kv[1]):
            add(findings, "TD32", "WARN", line, "icon '%s' is neither a Tabler name nor an alias of the theme's icon macro: renders an empty glyph" % icon)
    no_script = strip_scripts(text)
    hits = [line_of(text, m.start()) for m in re.finditer(r"\"\s*/>", strip_markup(no_script))]
    add_grouped(findings, "TD35", "WARN", hits, "stray '\" />' after visible text between tags: broken copy-paste, the quote and slash show in the page")
    hits = [line_of(text, m.start()) for m in re.finditer(r"\b(title|label|btnTitle|subtitle|legend|placeHolder)='([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ']+(?:\s+[A-Za-zÀ-ÿ'?!.]+)+)'", text) if "#i18n" not in m.group(2) and "${" not in m.group(2)]
    hits += [line_of(text, m.start()) for m in re.finditer(r"\bhome='([A-Za-zÀ-ÿ][^'$#]*)'", text)]
    add_grouped(findings, "TD36", "INFO", hits, "literal words in a label attribute without #i18n{}")
    hits = [line_of(text, m.start()) for m in re.finditer(r"params='[^']*style=", text)]
    add_grouped(findings, "TD38", "INFO", hits, "inline style= in params: the theme owns the CSS")
    check_house_forms(text, findings, kind)
    if know.css_classes:
        check_legacy_markup(text, findings, know, kind)
    for name, line in conditional_selectors(text):
        add(findings, "TD43", "WARN", line, "the script looks up '%s' unconditionally while the template only emits it inside a condition: the lookup returns null and the whole script block dies there" % name)
    if know.source.startswith("assembled"):
        for jsp, line in dead_links(text, know.webapps):
            add(findings, "TD44", "WARN", line, "link to %s, which the assembled webapp does not carry: the click answers 404" % jsp)
    hits = [line_of(text, m.start()) for m in re.finditer(r"<#(if|elseif)\b[^>]*&(gt|lt);", text)]
    add_grouped(findings, "TD26", "INFO", hits, "&gt;/&lt; inside a FreeMarker condition: write gt / lt")
    hits = [line_of(text, m.start()) for m in re.finditer(RAW_AMP, text)]
    add_grouped(findings, "TD06", "INFO", hits, "raw & between URL parameters in an href/action attribute: &amp; (targetUrl of an @offcanvas keeps raw &: offcanvas.ftl copies it into a script string)")
    hits = [line_of(text, m.start()) for m in re.finditer(IFRAME_AMP, text, flags=re.S)]
    add_grouped(findings, "TD07", "WARN", hits, "&amp; inside the targetUrl of an @offcanvas useIframe: offcanvas.ftl sets it through JS setAttribute, the iframe URL keeps a literal &amp; and the parameter is lost")


def dead_links(text, webapps):
    """(jsp path, line) of each literal jsp/ link or form action that no webapp directory carries as a file or a servlet mapping."""
    mapped = set()
    for w in webapps:
        for xml in [os.path.join(w, "WEB-INF/web.xml")] + glob.glob(os.path.join(w, "WEB-INF/plugins/*.xml")):
            if os.path.isfile(xml):
                mapped.update(p.strip().lstrip("/") for p in re.findall(r"<(?:servlet-)?url-pattern>([^<]+\.jsp)</", read(xml)))
    out = {}
    for match in re.finditer(r"""\b(?:href|action|targetUrl|url)\s*=\s*['"](?:\$\{[^}]*\}/?)?(jsp/(?:admin|site)/[A-Za-z0-9_/]+\.jsp)""", text):
        jsp = match.group(1)
        if jsp not in mapped and not any(os.path.isfile(os.path.join(w, jsp)) for w in webapps):
            out.setdefault(jsp, line_of(text, match.start()))
    return sorted(out.items(), key=lambda kv: kv[1])


def check_sql(text, findings):
    """SQL rules: the admin feature icon is a CSS class, adminHeader.ftl renders <i class="${iconUrl}">."""
    for match in re.finditer(r"INSERT INTO core_admin_right.*?;", text, flags=re.S | re.I):
        for icon in re.finditer(r"'(images/[^']*)'", match.group(0)):
            add(findings, "TD08", "WARN", line_of(text, match.start() + icon.start()), "core_admin_right icon_url '%s' is an image path: adminHeader.ftl renders it as a CSS class, use 'ti ti-<name>'" % icon.group(1))
        for row in re.finditer(r"\(([^()]*)\)", match.group(0)):
            cols = [c.strip() for c in row.group(1).split(",")]
            if len(cols) >= 9 and cols[8].upper() in ("NULL", "''"):
                add(findings, "TD08", "INFO", line_of(text, match.start() + row.start()), "core_admin_right row without icon_url: the feature shows no icon in the admin menu, give it 'ti ti-<name>'")


def scan_file(root, rel, scope, iframe_targets, know, jquery_declared=False):
    """Scan one file and return its report entry."""
    text = strip_comments(read(os.path.join(root, rel)))
    kind = classify(text, scope)
    findings = []
    if kind == "js":
        check_jquery(text, findings, jquery_declared)
        check_upload_widget(text, findings)
    elif kind == "sql":
        check_sql(text, findings)
    elif kind == "standalone":
        check_jquery(text, findings, jquery_declared)
        check_upload_widget(text, findings)
    elif kind == "email":
        add(findings, "TD10", "INFO", 1, "e-mail body template: out of scope, never convert to macros")
        for offset, _ in macro_calls(text, "cTpl"):
            add(findings, "TD40", "INFO", line_of(text, offset), "e-mail body carrying the @cTpl theme-override hook: decide whether a theme override of a mail body is intended, and check the file still parses (the pass that wrapped every skin template, core LUT-31677, left one of these unparseable)")
            break
    elif kind == "fo":
        check_skin(text, findings, know)
        check_common(text, findings, kind, know)
        check_jquery(text, findings, jquery_declared)
        check_upload_widget(text, findings)
    else:
        check_admin(text, findings, kind, os.path.basename(rel).rsplit(".", 1)[0] in iframe_targets, know)
        check_common(text, findings, kind, know)
        check_jquery(text, findings, jquery_declared)
        check_upload_widget(text, findings)
    findings.sort(key=lambda item: (item["line"], item["code"]))
    return {"path": rel, "kind": kind, "findings": findings}


def duplicate_macros(root, files):
    """Findings for macros defined in more than one template of the plugin."""
    seen = {}
    for rel in files:
        for match in MACRO_DEF.finditer(strip_comments(read(os.path.join(root, rel)))):
            seen.setdefault(match.group(1), []).append(rel)
    out = {}
    for name, paths in seen.items():
        if len(set(paths)) > 1:
            for rel in set(paths):
                out.setdefault(rel, []).append(name)
    return out


def walk(root, sub, ext):
    """List the files of one extension under a subdirectory, theme folders excluded."""
    base = os.path.join(root, sub)
    if not os.path.isdir(base):
        return []
    out = []
    for dirpath, _, files in os.walk(base):
        if "/themes/" in dirpath + "/":
            continue
        for name in files:
            if name.endswith(ext):
                out.append(os.path.relpath(os.path.join(dirpath, name), root))
    return sorted(out)


def main():
    """Entry point."""
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = os.path.abspath(args[0] if args else ".")
    as_json = "--json" in sys.argv
    flat = "--flat" in sys.argv
    warn_only = "--warn-only" in sys.argv
    know = Knowledge(root)
    if know.source == "reference clone" and "--no-exploded" not in sys.argv:
        print("no assembled webapp yet: running ensure-exploded.sh (mvn lutece:exploded-lite, it writes target/)", file=sys.stderr)
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ensure-exploded.sh")
        result = subprocess.run(["bash", script, root], capture_output=True, text=True)
        for line in result.stderr.splitlines():
            print("  " + line, file=sys.stderr)
        know = Knowledge(root)
        if know.source == "reference clone":
            print("scan not performed: the project could not be assembled, and the macro signatures, the icon font", file=sys.stderr)
            print("  and the templates it includes from its dependencies would come from a reference clone of", file=sys.stderr)
            print("  another version. Fix the build, or pass --no-exploded to accept the clone and say so in the report.", file=sys.stderr)
            return 2
    pom = os.path.join(root, "pom.xml")
    jquery_declared = "library-theme-jquery" in read(pom) if os.path.isfile(pom) else False
    admin_files = walk(root, ADMIN, ".html")
    skin_files = walk(root, SKIN, ".html")
    iframe_targets = set()
    for rel in admin_files:
        for match in CALL.finditer(strip_comments(read(os.path.join(root, rel)))):
            if match.group(1) == "offcanvas" and "useIframe=true" in match.group(2):
                target = re.search(r"targetUrl='([^'?]+\.jsp)", match.group(2))
                if target:
                    iframe_targets.add(jsp_to_template(target.group(1)))
    entries = []
    sql_files = [f for f in walk(root, SQL, ".sql") if "/upgrade/" not in f]
    js_files = walk(root, ADMIN, ".js") + walk(root, SKIN, ".js")
    for files, scope in ((admin_files, "admin"), (skin_files, "skin"), (js_files, "js"), (sql_files, "sql")):
        for rel in files:
            entries.append(scan_file(root, rel, scope, iframe_targets, know, jquery_declared))
    for code, rel in vendored_libraries(root):
        message = "upload widget library shipped by the project: " + UPLOAD_ADVICE + "; delete it once the screen uses the component" if code == "TD45" else "jQuery, or a jQuery plugin, shipped by the project: nothing updates this copy (jQuery before 3.5 carries known XSS flaws); port its callers to vanilla JS and delete it"
        entries.append({"path": rel, "kind": "vendored", "findings": [{"code": code, "severity": "WARN", "line": 1, "message": message}]})
    dupes = duplicate_macros(root, admin_files + skin_files)
    for entry in entries:
        if entry["path"] in dupes:
            add(entry["findings"], "TD39", "INFO", 1, "macro(s) %s also defined in another template: one shared macro_<plugin>.html included where needed" % ", ".join(sorted(dupes[entry["path"]])))
    if warn_only:
        for entry in entries:
            entry["findings"] = [f for f in entry["findings"] if f["severity"] == "WARN"]
    by_code = {}
    by_severity = {"WARN": 0, "INFO": 0}
    kinds = {}
    for entry in entries:
        kinds[entry["kind"]] = kinds.get(entry["kind"], 0) + 1
        for finding in entry["findings"]:
            by_code[finding["code"]] = by_code.get(finding["code"], 0) + 1
            by_severity[finding["severity"]] += 1
    report = {"root": root, "macroSource": know.source, "referencesAvailable": know.available, "files": entries, "summary": {"files": len(entries), "kinds": kinds, "bySeverity": by_severity, "byCode": dict(sorted(by_code.items()))}}
    if flat:
        for entry in entries:
            for finding in entry["findings"]:
                print("%s:%d %s %s %s" % (entry["path"], finding["line"], finding["code"], finding["severity"], finding["message"]))
        return 0
    if as_json:
        print(json.dumps(report, indent=2))
        return 0
    print("=== Template design scan: %s ===" % root)
    print("macros, signatures and icons read from: %s" % know.source)
    if not know.available:
        print("core reference clone missing: macro, signature and icon checks skipped")
    print("files: %d  %s" % (len(entries), " ".join("%s=%d" % kv for kv in sorted(kinds.items()))))
    for entry in entries:
        if entry["findings"]:
            print("\n%s  [%s]" % (entry["path"], entry["kind"]))
            for finding in entry["findings"]:
                print("  %s %-4s L%-4d %s" % (finding["code"], finding["severity"], finding["line"], finding["message"]))
    print("\n=== %d WARN, %d INFO  %s ===" % (by_severity["WARN"], by_severity["INFO"], " ".join("%s=%d" % kv for kv in sorted(by_code.items()))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
