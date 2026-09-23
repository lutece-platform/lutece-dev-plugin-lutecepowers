#!/usr/bin/env python3
"""Static inventory of a Lutece back office: features (rights), screens and actions, from the sources.

Sources read (any Lutece core, plugin, module or site tree):
  * SQL seeds:      INSERT INTO core_admin_right ... (init/create scripts only, never upgrade scripts: they
                    carry the urls of past versions)                -> features (right, entry url, group)
  * plugin.xml:     <admin-feature> ... <url>                    -> features
  * jsp/admin/**:   Xxx.jsp calling bean.getXxx / bean.doXxx     -> screens (GET) / actions (POST)
  * Java @Controller + @View / @Action                          -> MVC screens / actions
  * templates/admin/**: <form|@tform action=...>, href jsp/admin -> which screen reaches which action

Every element carries `origin`: "target" when it comes from the scanned tree (the artefact under test), "env" when
it was only found in an --extra tree (the core and the other plugins of the assembled site).
Output: JSON on stdout (features, screens, actions, stats). Stdlib only.
"""
import argparse
import contextlib
import json
import pathlib
import re
import sys

INCLUDE_JSP = re.compile(r"(Header|Footer|Menu|Frameset|SessionLess)\w*\.jsp$|^Error|^Popup|^AdminMessage")
RIGHT_SQL = re.compile(r"INSERT INTO core_admin_right\s*(?:\([^)]*\))?\s*VALUES\s*\((.*?)\);", re.I | re.S)
BEAN_CALL = re.compile(r"(\w+JspBean)\s*\.\s*(get|do|view|process)(\w+)\s*\(")
INIT_RIGHT = re.compile(r"\.init\s*\(\s*pageContext\.request\s*,\s*(?:\w+\.)?(\w+)\s*\)")
REDIRECT = re.compile(r"sendRedirect|response\.setHeader|\.do\w+\s*\(")
CONTROLLER = re.compile(r"@Controller\s*\(([^)]*)\)", re.S)
VIEW = re.compile(r"@View\s*\(\s*(?:value\s*=\s*)?(\w+|\"[^\"]+\")([^)]*)\)")
ACTION = re.compile(r"@Action\s*\(\s*(?:value\s*=\s*)?(\w+|\"[^\"]+\")")
CONST = re.compile(r"String\s+(\w+)\s*=\s*\"([^\"]+)\"")
FORM_ACTION = re.compile(r"<(?:form|@tform)\b[^>]*?action\s*=\s*['\"]([^'\"]*)['\"]", re.I | re.S)
HREF_ADMIN = re.compile(r"(?:href|action)\s*=\s*['\"]([^'\"]*jsp/admin/[^'\"#]*)", re.I)
TEMPLATE_REF = re.compile(r"TEMPLATE_\w+\s*=\s*\"([^\"]+\.html)\"")
# Detection rules of lutecedata (lutece_surface): the obvious proxies are wrong.
MVC_IMPORT = re.compile(r"import\s+fr\.paris\.lutece\.portal\.util\.mvc\.(commons|xpage|admin)\.annotations")
"""@View/@Action count only when the platform MVC annotations are imported: a plugin declaring its own @Action
would otherwise inject phantom actions."""
MVC_FRAMEWORK = re.compile(r"/portal/util/mvc/|/portal/service/content/XPageEventObserver\.java$")
"""The framework's own sources name xpageName and controllerJsp without being screens: excluded, or a core bench
reports the framework as its own surface."""
TEST_DIR = re.compile(r"(^|/)(test|tests)(/|$)")
CDI_XPAGE = re.compile(r'@Named\(\s*"([\w.-]+)\.xpage\.([\w-]+)"')
"""v8 XPage registered through CDI: @Named("<plugin>.xpage.<id>")."""
ADMIN_LITERAL = re.compile(r'"/?(admin/[\w./-]+\.(?:html|ftl))"')
"""An admin template named from Java: the only portable proxy for a back-office screen."""
NON_SCREEN_CLASS = re.compile(r"(DashboardComponent|TaskComponent|Servlet|PortletJspBean)$")
DECLARATIONS = {
    "daemons": re.compile(r"<daemon>"), "admin_features": re.compile(r"<admin-feature>"),
    "applications": re.compile(r"<application>"), "portlets": re.compile(r"<portlet>"),
    "rbac_resources": re.compile(r"<rbac-resource-type>"),
    "dashboards": re.compile(r"<(?:admin)?dashboard-component>"),
    "servlets": re.compile(r"<servlet>"), "filters": re.compile(r"<filter>"),
    "page_includes": re.compile(r"<page-include-service>"),
    "macro_files": re.compile(r"<freemarker-macro-file>"),
    "javascript_files": re.compile(r"<(?:admin-)?javascript-file>"),
    "stylesheets": re.compile(r"<(?:admin-)?css-stylesheet>"),
}


def in_build(path, root):
    """True for a file under a Maven target/ directory of the scanned tree (never for the tree itself, which may
    be an exploded webapp living under target/)."""
    parts = path.relative_to(root).parts
    # e2e/ holds the bench itself, including the v7 worktree of run.sh compare: none of it is the artefact.
    return "target" in parts or "e2e" in parts


def split_sql_values(raw):
    """Splits one SQL VALUES tuple into python values (quoted strings, numbers, NULL)."""
    out, buf, quoted, i = [], "", False, 0
    while i < len(raw):
        c = raw[i]
        if quoted:
            if c == "'" and i + 1 < len(raw) and raw[i + 1] == "'":
                buf += "'"; i += 1
            elif c == "'":
                quoted = False
            else:
                buf += c
        elif c == "'":
            quoted = True
        elif c == ",":
            out.append(buf.strip()); buf = ""
        else:
            buf += c
        i += 1
    out.append(buf.strip())
    return [None if v.upper() == "NULL" else v for v in out]


def features_from_sql(root):
    """Admin features seeded in core_admin_right (id_right, admin_url, group, plugin)."""
    feats = {}
    for sql in root.rglob("*.sql"):
        if in_build(sql, root) or "/upgrade/" in str(sql) or "/upgrades/" in str(sql):
            continue
        try:
            text = sql.read_text(errors="replace")
        except OSError:
            continue
        for m in RIGHT_SQL.finditer(text):
            v = split_sql_values(m.group(1))
            if len(v) < 8:
                continue
            feats[v[0]] = {"right": v[0], "url": v[3], "level": v[2], "group": v[7], "plugin": v[6] or "core",
                           "source": str(sql.relative_to(root))}
    return feats


def features_from_plugin_xml(root):
    """Admin features declared in WEB-INF/plugins/*.xml."""
    feats = {}
    for xml in root.rglob("WEB-INF/plugins/*.xml"):
        if in_build(xml, root):
            continue
        text = xml.read_text(errors="replace")
        plugin = (re.search(r"<name>([^<]+)</name>", text) or [None, xml.stem])[1]
        for block in re.finditer(r"<admin-feature>(.*?)</admin-feature>", text, re.S):
            b = block.group(1)
            fid = re.search(r"<feature-id>([^<]+)</feature-id>", b)
            url = re.search(r"<feature-url>([^<]+)</feature-url>", b)
            grp = re.search(r"<feature-group>([^<]+)</feature-group>", b)
            if fid:
                feats[fid.group(1).strip()] = {"right": fid.group(1).strip(), "url": url.group(1).strip() if url else None,
                                               "level": None, "group": grp.group(1).strip() if grp else None,
                                               "plugin": plugin.strip(), "source": str(xml.relative_to(root))}
    return feats


def fo_pages(root):
    """Front-office pages the tree declares outside MVC: one per <application-id> of a WEB-INF/plugins/*.xml, plus
    every v8 CDI XPage @Named("<plugin>.xpage.<id>"). Url is jsp/site/Portal.jsp?page=<id>. Their sub-navigation is
    parameter-driven and only the crawl finds it. MVC XPages (@Controller(xpageName=...)) come from mvc_inventory."""
    screens, seen = [], set()
    for xml in root.rglob("WEB-INF/plugins/*.xml"):
        if in_build(xml, root):
            continue
        text = xml.read_text(errors="replace")
        plugin = (re.search(r"<name>([^<]+)</name>", text) or [None, xml.stem])[1]
        for m in re.finditer(r"<application-id>([^<]+)</application-id>", text):
            pid = m.group(1).strip()
            if pid in seen:
                continue
            seen.add(pid)
            screens.append({"id": "xpage.%s" % pid, "url": "jsp/site/Portal.jsp?page=%s" % pid, "kind": "xpage",
                            "bean": None, "method": None, "right": None, "surface": "fo", "plugin": plugin.strip()})
    for java, rel in app_java(root):
        text = java.read_text(errors="replace")
        m = CDI_XPAGE.search(text)
        if not m or m.group(2) in seen:
            continue
        seen.add(m.group(2))
        screens.append({"id": "xpage.%s" % m.group(2), "url": "jsp/site/Portal.jsp?page=%s" % m.group(2),
                        "kind": "xpage-cdi", "bean": java.stem, "method": None, "right": None, "surface": "fo",
                        "plugin": m.group(1)})
    return screens, []


def jsp_inventory(root):
    """Every admin JSP, and every front-office JSP a plugin ships under jsp/site/plugins (downloads, callbacks),
    classified as screen or action, with the bean method it calls."""
    screens, actions = [], []
    for jsp in sorted(root.rglob("jsp/admin/**/*.jsp")):
        if in_build(jsp, root):
            continue
        rel = str(jsp).split("jsp/admin/", 1)[1]
        name = jsp.name
        if INCLUDE_JSP.search(name):
            continue
        text = jsp.read_text(errors="replace")
        call = BEAN_CALL.search(text)
        bean, verb, method = (call.group(1), call.group(2), call.group(2) + call.group(3)) if call else (None, None, None)
        right = INIT_RIGHT.search(text)
        entry = {"id": rel[:-4].replace("/", "."), "url": "jsp/admin/" + rel, "kind": "jsp", "bean": bean,
                 "method": method, "right": right.group(1) if right else None, "surface": "bo",
                 "needs_params": bean_params(root, bean, method)}
        is_action = name.startswith("Do") or verb in ("do", "process") or (REDIRECT.search(text) and verb != "get")
        (actions if is_action else screens).append(entry)
    for jsp in sorted(root.rglob("jsp/site/plugins/**/*.jsp")):
        if in_build(jsp, root) or INCLUDE_JSP.search(jsp.name):
            continue
        rel = str(jsp).split("jsp/site/", 1)[1]
        text = jsp.read_text(errors="replace")
        call = BEAN_CALL.search(text)
        bean, verb, method = (call.group(1), call.group(2), call.group(2) + call.group(3)) if call else (None, None, None)
        entry = {"id": "site." + rel[:-4].replace("/", "."), "url": "jsp/site/" + rel, "kind": "jsp", "bean": bean,
                 "method": method, "right": None, "surface": "fo", "needs_params": bean_params(root, bean, method)}
        is_action = jsp.name.startswith("Do") or verb in ("do", "process")
        (actions if is_action else screens).append(entry)
    return screens, actions



PARAM_CALL = re.compile(r'request\.getParameter\(\s*([A-Za-z0-9_."]+)\s*\)')


def bean_params(root, bean, method):
    """Request parameters the bean method reads, so a screen is never opened without what it requires.

    A JSP whose bean method reads `page_id` answers with an internal error when opened bare, and the bench would
    record a broken screen instead of testing it. The names come from the constant the code uses, resolved against
    the same class when it is declared there."""
    if not bean or not method:
        return []
    for java in root.rglob("*.java"):
        if in_build(java, root) or java.stem.lower() != bean.lower():
            continue
        text = java.read_text(errors="replace")
        m = re.search(r'\b%s\s*\([^)]*\)\s*\{' % re.escape(method), text)
        if not m:
            return []
        depth, i = 0, m.end() - 1
        while i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = text[m.end():i]
        for helper in set(re.findall(r'\b([a-z]\w*)\(\s*request\s*\)', body)):
            if helper == method:
                continue
            h = re.search(r'\b%s\s*\([^)]*\)\s*\{' % re.escape(helper), text)
            if not h:
                continue
            d2, j = 0, h.end() - 1
            while j < len(text):
                if text[j] == "{":
                    d2 += 1
                elif text[j] == "}":
                    d2 -= 1
                    if d2 == 0:
                        break
                j += 1
            body += text[h.end():j]
        names = []
        for raw in PARAM_CALL.findall(body):
            if raw.startswith('"'):
                names.append(raw.strip('"'))
                continue
            const = re.search(r'%s\s*=\s*"([^"]+)"' % re.escape(raw), text)
            if const:
                names.append(const.group(1))
            elif raw.startswith("PARAMETER_"):
                names.append(raw[len("PARAMETER_"):].lower())
        return sorted(set(names))
    return []

def app_java(root):
    """Java sources of the artefact itself: outside test roots, outside the MVC framework, outside target/."""
    for java in root.rglob("*.java"):
        rel = str(java.relative_to(root))
        if in_build(java, root) or TEST_DIR.search(rel) or MVC_FRAMEWORK.search("/" + rel):
            continue
        yield java, rel


REST_VERB = re.compile(r'@(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\b')
REST_PATH = re.compile(r'@Path\s*\(([^)]*)\)')
JAVA_CONST = re.compile(r'static\s+final\s+String\s+(\w+)\s*=\s*([^;]+);')
NAME_BINDING = re.compile(r'@NameBinding')
REST_METHOD = re.compile(r'((?:@\w+(?:\s*\([^)]*\))?\s*)+)(?:public|protected)\s+[\w<>\[\], .?]+\s+(\w+)\s*\(')


def rest_constants(root):
    """Every `static final String NAME = "value"` of the artefact, so a @Path built by concatenating constants
    resolves to the url a client actually calls. Plus the two plugin-rest constants, whose values are the reason
    a v8 @Path looks empty: BASE_PATH is "" and the /rest/ prefix lives on @ApplicationPath."""
    consts = {"RestConstants.BASE_PATH": "", "RestConstants.APP_PATH": "/rest/",
              "BASE_PATH": "", "APP_PATH": "/rest/"}
    # PLUGIN_NAME carries the path segment and usually lives in the plugin a module extends, outside this tree.
    # `XxxPlugin.PLUGIN_NAME` is the convention, and its value is the class prefix in lowercase — a module's own
    # descriptor name is NOT it (module-workflow-rest is named workflow-rest and serves /rest/workflow).
    for java, _ in app_java(root):
        for m in re.finditer(r"(\w+)Plugin\.PLUGIN_NAME", java.read_text(errors="replace")):
            consts.setdefault("%sPlugin.PLUGIN_NAME" % m.group(1), m.group(1).lower())
    for java, _ in app_java(root):
        text = java.read_text(errors="replace")
        for m in JAVA_CONST.finditer(text):
            consts.setdefault(m.group(1), m.group(2).strip())
            consts.setdefault("%s.%s" % (java.stem, m.group(1)), m.group(2).strip())
    return consts


def resolve_path(expr, consts, depth=0):
    """Resolves a @Path expression: string literals and constants joined by +, recursively, because a constant is
    often itself a concatenation (`VERSION_PATH = "/v{" + VERSION + "}"`). Returns None when a term is unknown —
    half a url is worse than none, it would send the bench at a path that does not exist."""
    if depth > 8:
        return None
    out = []
    for term in expr.split("+"):
        term = term.strip()
        if not term:
            continue
        if len(term) > 1 and term[0] == '"' and term[-1] == '"':
            out.append(term[1:-1])
            continue
        if term in ("StringUtils.EMPTY", "EMPTY"):
            continue
        value = consts.get(term, consts.get(term.split(".")[-1]))
        if value is None:
            return None
        if '"' in value or "+" in value:
            value = resolve_path(value, consts, depth + 1)
            if value is None:
                return None
        out.append(value)
    return "".join(out)


def rest_inventory(root):
    """JAX-RS resources of the artefact: one entry per resource method, with the url a client calls and whether
    the class carries a @NameBinding annotation of this artefact. That binding is what makes an authentication
    filter run on the resource; a resource without one is served unauthenticated and nothing in the build says so."""
    consts = rest_constants(root)
    bindings = set()
    for java, _ in app_java(root):
        text = java.read_text(errors="replace")
        if NAME_BINDING.search(text) and "@interface" in text:
            m = re.search(r'@interface\s+(\w+)', text)
            if m:
                bindings.add(m.group(1))
    screens, actions = [], []
    for java, rel in app_java(root):
        text = java.read_text(errors="replace")
        if "jakarta.ws.rs.Path" not in text:
            continue
        head = text.split("public ", 1)[0]
        cm = REST_PATH.search(head)
        if not cm:
            continue
        base = resolve_path(cm.group(1), consts)
        if base is None:
            continue
        bound = sorted(b for b in bindings if re.search(r'@%s\b' % b, head))
        for block in REST_METHOD.finditer(text):
            anns, meth = block.group(1), block.group(2)
            vm = REST_VERB.search(anns)
            if not vm:
                continue
            pm = REST_PATH.search(anns)
            sub = resolve_path(pm.group(1), consts) if pm else ""
            if sub is None:
                continue
            url = "rest/" + "/".join(x for x in (base.strip("/"), sub.strip("/")) if x)
            entry = {"id": "%s.%s" % (java.stem, meth), "url": url, "kind": "rest", "verb": vm.group(1),
                     "bean": java.stem, "method": meth, "right": None, "surface": "rest",
                     "name_bindings": bound, "unbound": not bound}
            (screens if vm.group(1) in ("GET", "HEAD", "OPTIONS") else actions).append(entry)
    return screens, actions


UNRESOLVED = []
"""Controllers whose @Controller arguments did not resolve: their screens are unknown, which the coverage gate reports."""


def constant_table(root):
    """String constants of the artefact's own sources, keyed by NAME and by Class.NAME: a @Controller or @View argument
    written as a constant resolves to its literal."""
    table = {}
    for java, _ in app_java(root):
        text = java.read_text(errors="replace")
        for name, value in CONST.findall(text):
            table.setdefault(name, value)
            table["%s.%s" % (java.stem, name)] = value
    return table


def resolve(expr, local, table):
    """Value of an annotation argument: a literal, a boolean, a constant (local, Class.NAME) or a concatenation of
    those; None when a part cannot be resolved."""
    parts = []
    for part in re.split(r"\s*\+\s*", expr.strip()):
        if re.fullmatch(r'"[^"]*"', part):
            parts.append(part[1:-1])
        elif part in ("true", "false"):
            parts.append(part)
        elif part in local:
            parts.append(local[part])
        elif part in table:
            parts.append(table[part])
        elif part.split(".")[-1] in local and "." in part:
            parts.append(local[part.split(".")[-1]])
        else:
            return None
    return "".join(parts)


def annotation_args(body, local, table):
    """name -> resolved value of the arguments of an annotation; unresolved names map to None."""
    args = {}
    for name, expr in re.findall(r"(\w+)\s*=\s*((?:\"[^\"]*\"|[\w.]+)(?:\s*\+\s*(?:\"[^\"]*\"|[\w.]+))*)", body):
        args[name] = resolve(expr, local, table)
    return args


def mvc_inventory(root):
    """MVC controllers, front and back. A controller is front office when it carries xpageName (its screens are
    Portal.jsp?page=<name>&view=<v>), back office when it carries controllerJsp. @View/@Action are only read when
    the file imports the platform MVC annotations."""
    screens, actions = [], []
    table = constant_table(root)
    for java, rel in app_java(root):
        text = java.read_text(errors="replace")
        ctl = CONTROLLER.search(text)
        if not ctl:
            continue
        consts = dict(CONST.findall(text))
        attrs = annotation_args(ctl.group(1), consts, table)
        if not MVC_IMPORT.search(text):
            continue
        unresolved = [k for k in ("controllerJsp", "controllerPath", "xpageName") if k in attrs and attrs[k] is None]
        if unresolved:
            print("inventory: %s: @Controller %s not resolved to a literal, its screens and actions are missing from the inventory" % (rel, ", ".join(unresolved)), file=sys.stderr)
            UNRESOLVED.append({"file": str(rel), "attributes": unresolved})
        bean = java.stem
        page = attrs.get("xpageName")
        if page:
            base, surface, kind = "jsp/site/Portal.jsp?page=%s" % page, "fo", "xpage-mvc"
            sep = "&"
        else:
            base = attrs.get("controllerPath", "") + attrs.get("controllerJsp", "")
            surface, kind, sep = "bo", "mvc", "?"
            if not base:
                continue
        for m in VIEW.finditer(text):
            v = consts.get(m.group(1), m.group(1).strip('"'))
            default = "defaultView" in m.group(2) and "true" in m.group(2)
            screens.append({"id": "%s.view.%s" % (bean, v), "url": "%s%sview=%s" % (base, sep, v), "kind": kind,
                            "bean": bean, "method": v, "right": attrs.get("right"), "default": default,
                            "surface": surface})
        for m in ACTION.finditer(text):
            a = consts.get(m.group(1), m.group(1).strip('"'))
            actions.append({"id": "%s.action.%s" % (bean, a), "url": "%s%saction=%s" % (base, sep, a), "kind": kind,
                            "bean": bean, "method": a, "right": attrs.get("right"),
                            "token": attrs.get("securityTokenEnabled") == "true", "surface": surface})
    return screens, actions


def java_package(root):
    """Longest Java package prefix shared by the artefact's own sources (fr.paris.lutece.plugins.myplugin for a
    plugin, fr.paris.lutece for the core). Used to tell an exception raised by the artefact from the noise of the
    platform it runs inside."""
    pkgs = []
    for java, rel in app_java(root):
        m = re.search(r"^\s*package\s+([\w.]+)\s*;", java.read_text(errors="replace"), re.M)
        if m:
            pkgs.append(m.group(1).split("."))
    if not pkgs:
        return None
    prefix = pkgs[0]
    for parts in pkgs[1:]:
        prefix = [a for a, b in zip(prefix, parts) if a == b]
    return ".".join(prefix) or None


def artefact_markers(root, pkg):
    """Strings that identify the artefact in a server-log line, so an exception can be attributed to it even when no
    Java frame of its own appears: its package, the plugin names it declares, its template directories and the
    prefixes of the tables its SQL creates. A plugin breaks the core through its own templates, SQL or descriptor
    just as often as through a direct call."""
    marks = set()
    if pkg:
        marks.add(pkg)
    names = set()
    for xml in root.rglob("WEB-INF/plugins/*.xml"):
        if in_build(xml, root):
            continue
        m = re.search(r"<name>([^<]+)</name>", xml.read_text(errors="replace"))
        if m:
            names.add(m.group(1).strip())
    for n in names:
        marks.add("plugins/%s/" % n)
    for d in list(root.rglob("templates/admin/plugins/*")) + list(root.rglob("templates/skin/plugins/*")):
        if not d.is_dir() or in_build(d, root):
            continue
        children = [c for c in d.iterdir()]
        if children and all(c.is_dir() and c.name == "modules" for c in children):
            marks.update("plugins/%s/modules/%s/" % (d.name, m.name) for m in (d / "modules").iterdir() if m.is_dir())
        else:
            marks.add("plugins/%s/" % d.name)
    for sql in root.rglob("*.sql"):
        if in_build(sql, root) or "/upgrade" in str(sql):
            continue
        for t in re.findall(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[`\"]?(\w+)", sql.read_text(errors="replace"), re.I):
            marks.add(t.lower())
    return sorted(m for m in marks if len(m) > 3)


def declarations(root):
    """What the plugin descriptors declare: menu entries, applications, RBAC resources, dashboards, portlets,
    daemons, servlets, filters, page includes, macro and asset files. The socle the agent must also cover."""
    counts = {k: 0 for k in DECLARATIONS}
    for xml in root.rglob("WEB-INF/plugins/*.xml"):
        if in_build(xml, root):
            continue
        text = xml.read_text(errors="replace")
        for key, pat in DECLARATIONS.items():
            counts[key] += len(pat.findall(text))
    return counts


def java_surface(root):
    """Controller and template evidence used to size the real screen surface (see the module docstring rules)."""
    out = {"controllers_fo": 0, "controllers_bo": 0, "views_fo": 0, "views_bo": 0, "actions_fo": 0,
           "actions_bo": 0, "cdi_xpages": 0}
    cited = set()
    for java, rel in app_java(root):
        text = java.read_text(errors="replace")
        is_fo, is_bo = "xpageName" in text, "controllerJsp" in text
        mvc = bool(MVC_IMPORT.search(text))
        if is_fo:
            out["controllers_fo"] += 1
            out["views_fo"] += len(VIEW.findall(text)) if mvc else 0
            out["actions_fo"] += len(ACTION.findall(text)) if mvc else 0
        if is_bo:
            out["controllers_bo"] += 1
            out["views_bo"] += len(VIEW.findall(text)) if mvc else 0
            out["actions_bo"] += len(ACTION.findall(text)) if mvc else 0
        if CDI_XPAGE.search(text):
            out["cdi_xpages"] += 1
        if not NON_SCREEN_CLASS.search(java.stem):
            cited.update(ADMIN_LITERAL.findall(text))
    out["admin_cited"] = sorted(cited)
    return out


def template_links(root):
    """Form actions and admin links found in each admin template."""
    links = {}
    for html in root.rglob("templates/admin/**/*.html"):
        if in_build(html, root):
            continue
        text = html.read_text(errors="replace")
        rel = str(html).split("templates/", 1)[1]
        forms = sorted({a for a in FORM_ACTION.findall(text) if a and "${" not in a})
        hrefs = sorted({h.split("?")[0] for h in HREF_ADMIN.findall(text) if "${" not in h.split("?")[0]})
        if forms or hrefs:
            links[rel] = {"forms": forms, "links": hrefs}
    return links


def bean_templates(root):
    """Which templates each JspBean renders (TEMPLATE_* constants)."""
    out = {}
    for java in root.rglob("*JspBean.java"):
        if in_build(java, root):
            continue
        out[java.stem] = sorted(set(TEMPLATE_REF.findall(java.read_text(errors="replace"))))
    return out


def print_markdown(inv, surface):
    """The compact markdown summary of an inventory, printed on stdout."""
    u = surface["testable_urls"]
    print("# Surface de `%s`\n" % pathlib.Path(inv["root"]).name)
    print("Ce que la cible expose (comptages calibrés : un écran back-office est un template `admin/` nommé depuis")
    print("le Java, pas un fichier JSP — les JSP sont des points d'entrée et sur-comptent les écrans).\n")
    print("| Écrans | n | | Actions | n |\n|---|---|---|---|---|")
    print("| back-office | %d | | back-office (MVC) | %d |" % (surface["screens_bo"], surface["actions_bo"]))
    print("| front-office | %d | | front-office (MVC) | %d |" % (surface["screens_fo"], surface["actions_fo"]))
    print("| points d'entrée JSP admin | %d | | **URLs testables** | **%d écrans / %d actions** |"
          % (surface["jsp_admin_entrypoints"], u["screens"], u["actions"]))
    rest_tgt = [x for x in inv["rest"] if x["origin"] == "target"]
    if rest_tgt:
        print("\n## Points REST\n")
        print("Une ressource JAX-RS n'est pas un écran : un navigateur ne la juge pas. Elle se teste avec l'étape")
        print("`http` d'un scénario, et `sign` quand le plugin la protège.\n")
        print("| Verbe | URL | Liaison d'authentification |\n|---|---|---|")
        for e in rest_tgt:
            print("| %s | `%s` | %s |" % (e["verb"], e["url"], ", ".join(e["name_bindings"]) or "**aucune**"))
        if surface["rest_unbound"]:
            print("\n**%d classe(s) sans liaison d'authentification** : %s. Leurs points sont servis sans contrôle,"
                  % (len(surface["rest_unbound"]), ", ".join(surface["rest_unbound"])))
            print("et rien dans la construction ne le signale. C'est à vérifier, pas à supposer : soit le plugin")
            print("n'a jamais rien protégé, soit sa protection est tombée à la migration.")
    print("\n| Socle déclaré | n |\n|---|---|")
    for k, label in (("admin_features", "entrées de menu admin"), ("applications", "applications front"),
                     ("rbac_resources", "ressources RBAC"), ("dashboards", "dashboards"),
                     ("portlets", "portlets"), ("daemons", "daemons"), ("servlets", "servlets"),
                     ("filters", "filtres"), ("page_includes", "page includes"),
                     ("macro_files", "fichiers de macros"), ("javascript_files", "fichiers JS"),
                     ("stylesheets", "feuilles de style")):
        if surface.get(k):
            print("| %s | %d |" % (label, surface[k]))
    print("\n| Code | n |\n|---|---|")
    print("| contrôleurs MVC back-office | %d |" % surface["controllers_bo"])
    print("| contrôleurs MVC front-office | %d |" % surface["controllers_fo"])
    print("| XPages CDI (@Named …xpage…) | %d |" % surface["cdi_xpages"])
    print("| templates admin | %d dont %d nommés depuis le Java |"
          % (surface["admin_templates"], surface["admin_templates_named_from_java"]))
    unnamed = surface["admin_templates_unnamed"]
    if unnamed:
        print("\n%d template(s) admin qu'aucun Java ne nomme (macros, includes, ou écran mort) : %s"
              % (len(unnamed), ", ".join("`%s`" % x for x in unnamed[:15])))
    if inv["features"]:
        print("\n| Fonctionnalité (droit) | Écran d'entrée | Groupe |\n|---|---|---|")
        for f in inv["features"]:
            print("| %s | %s | %s |" % (f["right"], f["url"] or "-", f["group"] or "-"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", nargs="?", default=".", help="source tree (core, plugin, module or site)")
    ap.add_argument("--extra", action="append", default=[], help="additional tree to scan: the exploded webapp of the "
                    "assembled site (plugins pulled from Maven, without local sources) or a plugin source checkout")
    ap.add_argument("--markdown", action="store_true", help="print a compact markdown table instead of JSON")
    ap.add_argument("--markdown-out", help="also write the markdown table to this file, in the same pass as the JSON")
    args = ap.parse_args()
    root = pathlib.Path(args.root).resolve()
    roots = [root] + [pathlib.Path(x).resolve() for x in args.extra if pathlib.Path(x).exists()]

    feats, screens, actions, links, templates = {}, [], [], {}, {}
    rest = []
    seen, seen_rest = set(), set()
    for n, r in enumerate(roots):
        origin = "target" if n == 0 else "env"
        for k, v in list(features_from_sql(r).items()) + list(features_from_plugin_xml(r).items()):
            if k not in feats:
                v["origin"] = origin; feats[k] = v
        js, ja = jsp_inventory(r)
        ms, ma = mvc_inventory(r)
        fs, fa = fo_pages(r)
        rs, ra = rest_inventory(r)
        for e in rs + ra:                                  # never in screens/actions: no browser suite may open a
            if e["url"] not in seen_rest:                  # REST endpoint, it negotiates a representation nobody
                e["origin"] = origin; seen_rest.add(e["url"]); rest.append(e)   # asked for and judges markup that
        for e in js + ms + fs:                             # does not exist. The http step of a scenario tests it.
            if e["url"] not in seen:
                e["origin"] = origin; seen.add(e["url"]); screens.append(e)
        for e in ja + ma + fa:
            if e["url"] not in seen:
                e["origin"] = origin; seen.add(e["url"]); actions.append(e)
        links.update(template_links(r))
        templates.update(bean_templates(r))
        if n == 0:                                        # the surface measures the artefact under test only
            decl, jsurf, pkg = declarations(r), java_surface(r), java_package(r)
            marks = artefact_markers(r, pkg)
            admin_tpl = sorted({str(h).split("templates/", 1)[1] for h in r.rglob("templates/admin/**/*.html")
                                if not in_build(h, r)} | {str(h).split("templates/", 1)[1]
                                for h in r.rglob("templates/admin/**/*.ftl") if not in_build(h, r)})

    by_url = {"jsp/admin/" + s["url"].split("jsp/admin/", 1)[1].split("?")[0]: s for s in screens if "jsp/admin/" in s["url"]}
    for tpl, l in links.items():
        beans = [b for b, ts in templates.items() if tpl in ts]
        for s in screens:
            if s["bean"] in beans:
                s.setdefault("templates", []).append(tpl)
                s.setdefault("reaches", [])
                s["reaches"] = sorted(set(s["reaches"] + l["forms"] + l["links"]))
    entry_urls = {f["url"] for f in feats.values() if f.get("url")}
    for s in screens:
        s["entry"] = s["url"] in entry_urls

    tgt = [x for x in screens if x["origin"] == "target"]
    tga = [x for x in actions if x["origin"] == "target"]
    # Screen counts use these proxies, not the raw file counts: an admin JSP is an entry point (it
    # over-counts screens several fold), a back-office screen is an admin template named from Java (else the back
    # controllers' @View), a front-office screen is a front controller's @View else a declared XPage.
    screens_bo = len(jsurf["admin_cited"]) or jsurf["views_bo"]
    screens_fo = jsurf["views_fo"] or len([x for x in tgt if x["surface"] == "fo"])
    surface = {"screens_bo": screens_bo, "screens_fo": screens_fo,
               "actions_bo": jsurf["actions_bo"], "actions_fo": jsurf["actions_fo"],
               "jsp_admin_entrypoints": sum(1 for x in tgt if x["kind"] == "jsp"),
               "controllers_bo": jsurf["controllers_bo"], "controllers_fo": jsurf["controllers_fo"],
               "cdi_xpages": jsurf["cdi_xpages"], "admin_templates": len(admin_tpl),
               "admin_templates_named_from_java": len(jsurf["admin_cited"]),
               "admin_templates_unnamed": sorted(set(admin_tpl) - {"admin/" + c.split("admin/", 1)[1]
                                                                   for c in jsurf["admin_cited"]}),
               "rest_endpoints": sum(1 for x in rest if x["origin"] == "target"),
               "rest_unbound": sorted({x["bean"] for x in rest if x["origin"] == "target" and x.get("unbound")}),
               "package": pkg, "markers": marks,
               "testable_urls": {"screens": len(tgt), "actions": len(tga)}}
    surface.update(decl)
    inv = {"root": str(root), "extra": [str(r) for r in roots[1:]], "surface": surface, "unresolved_controllers": UNRESOLVED,
           "features": sorted(feats.values(), key=lambda f: f["right"]),
           "screens": sorted(screens, key=lambda s: s["id"]), "actions": sorted(actions, key=lambda a: a["id"]),
           "rest": sorted(rest, key=lambda r: (r["url"], r["verb"])),
           "stats": {"features": len(feats), "screens": len(screens), "actions": len(actions),
                     "templates_with_links": len(links),
                     "target_screens": sum(1 for s in screens if s["origin"] == "target"),
                     "target_actions": sum(1 for a in actions if a["origin"] == "target"),
                     "fo_screens": sum(1 for s in screens if s.get("surface") == "fo"),
                     "fo_actions": sum(1 for a in actions if a.get("surface") == "fo"),
                     "rest": len(rest)}}
    if args.markdown:
        print_markdown(inv, surface)
        return
    if args.markdown_out:
        with open(args.markdown_out, "w", encoding="utf-8") as out, contextlib.redirect_stdout(out):
            print_markdown(inv, surface)
    json.dump(inv, sys.stdout, indent=1, ensure_ascii=False)
    print()


if __name__ == "__main__":
    main()
