#!/usr/bin/env python3
"""site_check.py — the checks of a Lutece site (packaging lutece-site, a site or a pack) that no other tool makes.

Usage:
  site_check.py check  <site_dir> [--war DIR] [--k8s DIR] [--before DIR --before-ref REF] [--decisions FILE] [--m2 DIR] [--bom POM]
  site_check.py gate   <war_dir> [--site DIR] [--bom POM] [--m2 DIR] [--repo-url URL]... [--offline]
  site_check.py config <war_dir> [--profile NAME] [--against DUMP]
  site_check.py envconf <site_dir> [--out FILE]
  site_check.py plugins-dat <war_dir>
  site_check.py spring <site_dir> --war DIR
  site_check.py rebase <site_dir> --before DIR --before-m2 DIR --war DIR --m2 DIR [--write]
  site_check.py takeover <before_war> <after_war> --out DIR

check   checks the site sources and, with --war, the site assembled from them (the directory lutece:site-assembly
        explodes under target/). With --before (the same site assembled before the update: its v7 state, or its
        previous v8 state) and --before-ref (the git ref of the site sources that produced it), every difference of
        what the site ships (an effective configuration value, a plugin, a file of the site overlay, the profiles
        it names) is a finding until the decisions file (default: <site_dir>/.migration/site-decisions.md) answers
        it with a line `- key|plugin|file|profile <id>: <reason>`. Prints `  PASS|INFO|WARN|FAIL [SIxx] ...`, one
        line per finding, and exits 1 when a FAIL is reported. A site set up for several replicas (cluster.xml,
        sessionCache-1.0, sessionDatabase-1.0 or a Hazelcast dependency) is also checked on its multi-instance
        configuration (SI60-SI68), and with --k8s on its Kubernetes manifests or chart templates (SI70-SI72).
gate    the Lutece 8 status of every Lutece artefact an assembled site ships (read from the pom.properties of its
        jars): managed by the target lutece-bom, published with a Lutece 8 parent, or without any Lutece 8 version.
        Exits 1 when one artefact has no Lutece 8 version: it has to be updated first (lutece-update-plugin).
config  the effective configuration of an assembled site: every key, its value and the source that wins, computed
        the way the core and MicroProfile Config resolve it. With --against, the dump the running site printed
        (site-config-dump.jsp: one `key=value` per line) is compared with it: a key the model resolves otherwise
        is a finding, the model is only trusted where it agrees with the container.
envconf the per-environment configuration of a v7 site (src/conf/<env>/, one copy per environment, which
        lutece-site-pom does not copy) written as one override file with MicroProfile profile keys: a value every environment
        shares is a plain key, a value that differs is %<env>.key. Prints the draft, every line annotated with the files
        it comes from, then the files it cannot convert (Spring contexts, templates, db.properties, log.properties).
spring  the Spring contexts of a v7 site (webapp/ and every src/conf/<env>/) as keys of the v8 war: for each bean
        property, the key <bean id>.<property> when a class or a default of the war names it, else the keys of the
        war ending with .<property>, as candidates to read in the plugin's sources; a value is written under the profile
        of the environment it comes from, a secret is never copied.
rebase  every file of the site overlay that replaces a file of a dependency, replayed on the dependency's new version:
        a three-way merge (git merge-file) of the v7 upstream (base), the v8 upstream and the site's file. Prints, per
        file, the lines the site changed and whether they apply cleanly; --write replaces the site's file by the merge
        when it has no conflict, and writes <file>.conflict next to it otherwise.
takeover the two SQL scripts that let the after war take over the database of the before site, one per normal start
        after the start in migration mode: takeover-1-core.sql (only the core upgrades run), takeover-2-components.sql
        (each component back to what the before site had installed, the keys of a renamed component moved to its new
        name, the version of a new one removed so its create and init scripts run). Prints SI13-SI14 for this takeover.
plugins-dat  the plugins.dat of an assembled site, from the plugin descriptors it ships: <name>.installed=1 for each,
        <name>.pool=portal when the descriptor requires a pool, core_extensions.installed=1.

The effective configuration follows lutece-core and SmallRye Config as measured: in v8, jar
META-INF/microprofile-config.properties at 100, LuteceConfigSource at 150 (the seven root files of WEB-INF/conf, then
conf/plugins and conf/themes), a ConfigSource a jar ships at the constant its getOrdinal( ) returns (read in its
bytecode) with the properties files at the root of that jar, and LuteceOverrideConfigSource at 250 (conf/override and conf/override/plugins). Inside a source the files load in
the order of FileSorterUtil.sortByPropertiesPrecedence (plugins, themes, override, override/plugins, then the path in
alphabetical order) and the last one loaded wins. A profile resolves source by source: in one
source %<profile>.key wins over key, and a source of higher ordinal wins over a lower one whatever the profile. An
empty value masks the key: the property is absent, the caller's default applies. In v7 there is one source: the
seven root files, then plugins/, themes/, override/, override/plugins/, each directory in file system order.
"""
import argparse
import json
import os
import pathlib
import re
import struct
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sql_paths  # noqa: E402

ROOT_FILES = ("config", "db", "lutece", "search", "daemons", "caches", "editors")
REPOSITORIES = ("https://dev.lutece.paris.fr/maven_repository", "https://dev.lutece.paris.fr/snapshot_repository")
CLASS_VALUE = re.compile(r"(?:[a-z_][a-z0-9_]*\.){2,}[A-Z][A-Za-z0-9_$]*")
JDK_PACKAGES = ("com.sun.", "org.w3c.", "org.xml.", "org.ietf.")
class SecretKey:
    """Tells whether a key names a secret: its last segment ends with a secret word, or names a password or a secret."""

    END = re.compile(r"(passw(or)?d|pwd|secret|token|credentials?|apikey|api[_-]?key|privatekey)$", re.I)
    ANY = re.compile(r"(password|secret)", re.I)

    def search(self, key):
        """Returns a truthy value when the key names a secret."""
        last = key.rsplit(".", 1)[-1]
        return self.END.search(last) or self.ANY.search(last)


SECRET_KEY = SecretKey()


def shown_value(key, value):
    """A value as the tool prints it: a secret is never printed, only whether it is set."""
    if value is None:
        return value
    return "***** (secret, not printed)" if SECRET_KEY.search(key) and value.strip() else value
PLACEHOLDER = re.compile(r"^(\$\{.*\}|<.*>|x{3,}|changeme|a[-_ ]renseigner|todo|none|null|)$", re.I)
KEY_LIKE = re.compile(r"[A-Za-z0-9_\-]+(?:\.[A-Za-z0-9_\-]+)+")
DECISION = re.compile(r"^\s*-\s+(key|plugin|file|profile)\s+(\S+?)\s*:\s*(\S.*)$")
OVERRIDE_FILE = re.compile(r"WEB-INF/conf/override/(?:plugins/)?[^/]+\.properties")
POM_NS = {"m": "http://maven.apache.org/POM/4.0.0"}
REMOVED_MACROS = ("initXssBypass", "NbItemsPerPageSelectorCombo", "NbItemsPerPageSelectorRadioList")


class Findings:
    """Collects the findings of a run and prints them the way lutece-check.sh reads them."""

    def __init__(self):
        """Starts with no finding."""
        self.lines = []
        self.fail = False

    def add(self, severity, code, message):
        """Records one finding; a FAIL makes the run exit 1."""
        self.lines.append(f"  {severity} [{code}] {message}")
        self.fail = self.fail or severity == "FAIL"

    def passed(self, code, message):
        """Records a check that found nothing."""
        self.lines.append(f"  PASS [{code}] {message}")

    def print(self):
        """Prints every finding, then the totals."""
        for line in self.lines:
            print(line)
        counts = {s: sum(1 for l in self.lines if l.startswith(f"  {s} ")) for s in ("PASS", "INFO", "WARN", "FAIL")}
        print(f"TOTAL: {len(self.lines)} lines, PASS {counts['PASS']}, INFO {counts['INFO']}, WARN {counts['WARN']}, FAIL {counts['FAIL']}")


def unescape(text):
    """Decodes the escapes of a java.util.Properties key or value."""
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if c != "\\" or i + 1 == len(text):
            out.append(c)
            i += 1
            continue
        n = text[i + 1]
        if n == "u" and re.fullmatch(r"[0-9a-fA-F]{4}", text[i + 2:i + 6]):
            out.append(chr(int(text[i + 2:i + 6], 16)))
            i += 6
            continue
        out.append({"t": "\t", "n": "\n", "r": "\r", "f": "\f"}.get(n, n))
        i += 2
    return "".join(out)


def parse_properties(text):
    """Parses java.util.Properties text into (key, value) pairs in file order, continuation lines joined."""
    pairs, logical, pending = [], [], None
    for raw in text.splitlines():
        line = raw.lstrip(" \t\f")
        if pending is None and (not line or line[0] in "#!"):
            continue
        tail = len(line) - len(line.rstrip("\\"))
        if tail % 2 == 1:
            pending = (pending or "") + line[:-1]
            continue
        logical.append((pending or "") + line)
        pending = None
    if pending is not None:
        logical.append(pending)
    for line in logical:
        i, key = 0, []
        while i < len(line) and line[i] not in "=: \t\f":
            if line[i] == "\\" and i + 1 < len(line):
                key.append(line[i:i + 2])
                i += 2
                continue
            key.append(line[i])
            i += 1
        while i < len(line) and line[i] in " \t\f":
            i += 1
        if i < len(line) and line[i] in "=:":
            i += 1
        while i < len(line) and line[i] in " \t\f":
            i += 1
        pairs.append((unescape("".join(key)), unescape(line[i:])))
    return pairs


def escape_value(value):
    """Writes a value for a .properties file read as ISO-8859-1: backslashes, line breaks, a leading space and every
    non-ASCII character escaped, so that java.util.Properties reads back exactly the value."""
    out = value.replace("\\", "\\\\").replace("\r", "\\r").replace("\n", "\\n")
    out = ("\\ " + out[1:]) if out.startswith(" ") else out
    return "".join(c if ord(c) < 128 else f"\\u{ord(c):04x}" for c in out)


def properties_precedence(path):
    """Loading rank of a properties file inside its source, as FileSorterUtil.sortByPropertiesPrecedence sorts it:
    plugins, themes, override, override/plugins, then the path; the last one loaded wins."""
    path = "/" + path.lstrip("/")
    for rank, segment in ((4, "/conf/override/plugins/"), (3, "/conf/override/"), (2, "/conf/themes/"), (1, "/conf/plugins/")):
        if segment in path:
            return rank, path
    return 0, path


def read_properties(path):
    """Reads a properties file as ISO-8859-1, the encoding java.util.Properties.load uses."""
    return parse_properties(pathlib.Path(path).read_text(encoding="latin-1"))


def utf8_constants(data):
    """Returns the CONSTANT_Utf8 entries of a class file, or an empty list when it cannot be parsed."""
    if data[:4] != b"\xca\xfe\xba\xbe":
        return []
    out = []
    try:
        count, pos, index = struct.unpack(">H", data[8:10])[0], 10, 1
        sizes = {3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4, 11: 4, 12: 4, 15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}
        while index < count:
            tag = data[pos]
            if tag == 1:
                length = struct.unpack(">H", data[pos + 1:pos + 3])[0]
                out.append(data[pos + 3:pos + 3 + length].decode("utf-8", "replace"))
                pos += 3 + length
            else:
                pos += 1 + sizes[tag]
            index += 2 if tag in (5, 6) else 1
    except (KeyError, IndexError, struct.error):
        return out
    return out


def class_bean_name(data):
    """(class name, CDI bean name, plain bean) of a class annotated @Named, the bean name being the annotation's value
    or the simple class name with a lower-case first letter, plain meaning scoped, neither an alternative (CDI prefers
    it to a plain bean of the same name) nor vetoed; None for any other class or an unreadable one."""
    u2 = lambda at: struct.unpack(">H", data[at:at + 2])[0]
    u4 = lambda at: struct.unpack(">I", data[at:at + 4])[0]
    try:
        if data[:4] != b"\xca\xfe\xba\xbe":
            return None
        count, pos, index, pool, refs = u2(8), 10, 1, {}, {}
        sizes = {3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4, 11: 4, 12: 4, 15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}
        while index < count:
            tag = data[pos]
            if tag == 1:
                pool[index] = data[pos + 3:pos + 3 + u2(pos + 1)].decode("utf-8", "replace")
                pos += 3 + u2(pos + 1)
            else:
                if tag == 7:
                    refs[index] = u2(pos + 1)
                pos += 1 + sizes[tag]
            index += 2 if tag in (5, 6) else 1
        this = pool.get(refs.get(u2(pos + 2)), "").replace("/", ".")
        pos += 6
        pos += 2 + 2 * u2(pos)
        for _ in ("field", "method"):
            n, pos = u2(pos), pos + 2
            for _ in range(n):
                attrs, pos = u2(pos + 6), pos + 8
                for _ in range(attrs):
                    pos += 6 + u4(pos + 2)

        def skip_value(at):
            tag = chr(data[at])
            if tag in "BCDFIJSZsc":
                return at + 3
            if tag == "e":
                return at + 5
            if tag == "@":
                return skip_annotation(at + 1)[0]
            if tag == "[":
                n, at = u2(at + 1), at + 3
                for _ in range(n):
                    at = skip_value(at)
                return at
            raise ValueError(tag)

        def skip_annotation(at):
            kind, n, at, values = pool.get(u2(at)), u2(at + 2), at + 4, {}
            for _ in range(n):
                name = pool.get(u2(at))
                if chr(data[at + 2]) == "s":
                    values[name] = pool.get(u2(at + 3))
                at = skip_value(at + 2)
            return at, kind, values

        annotations = {}
        n, pos = u2(pos), pos + 2
        for _ in range(n):
            aname, alen = pool.get(u2(pos)), u4(pos + 2)
            if aname == "RuntimeVisibleAnnotations":
                at = pos + 8
                for _ in range(u2(pos + 6)):
                    at, kind, values = skip_annotation(at)
                    annotations[kind] = values
            pos += 6 + alen
    except (KeyError, IndexError, ValueError, struct.error):
        return None
    if "Ljakarta/inject/Named;" not in annotations:
        return None
    simple = this.rsplit(".", 1)[-1].split("$")[-1]
    name = annotations["Ljakarta/inject/Named;"].get("value") or (simple[:1].lower() + simple[1:])
    plain = any(k.startswith("Ljakarta/enterprise/context/") for k in annotations) and not (
        {"Ljakarta/enterprise/inject/Alternative;", "Ljakarta/enterprise/inject/Vetoed;"} & annotations.keys())
    return this, name, plain


def class_ordinal(data):
    """The constant a ConfigSource class returns from getOrdinal( ), read in its bytecode, or -1 when the method
    computes it (reads a property, calls something) or the class cannot be parsed."""
    u2 = lambda at: struct.unpack(">H", data[at:at + 2])[0]
    u4 = lambda at: struct.unpack(">I", data[at:at + 4])[0]
    try:
        count, pos, index, pool = u2(8), 10, 1, {}
        sizes = {3: 4, 4: 4, 5: 8, 6: 8, 7: 2, 8: 2, 9: 4, 10: 4, 11: 4, 12: 4, 15: 3, 16: 2, 17: 4, 18: 4, 19: 2, 20: 2}
        while index < count:
            tag = data[pos]
            if tag == 1:
                pool[index] = data[pos + 3:pos + 3 + u2(pos + 1)].decode("utf-8", "replace")
                pos += 3 + u2(pos + 1)
            else:
                if tag == 3:
                    pool[index] = struct.unpack(">i", data[pos + 1:pos + 5])[0]
                pos += 1 + sizes[tag]
            index += 2 if tag in (5, 6) else 1
        pos += 6
        pos += 2 + 2 * u2(pos)
        for member in ("field", "method"):
            n, pos = u2(pos), pos + 2
            for _ in range(n):
                name, desc, attrs, pos = pool.get(u2(pos + 2)), pool.get(u2(pos + 4)), u2(pos + 6), pos + 8
                for _ in range(attrs):
                    aname, alen = pool.get(u2(pos)), u4(pos + 2)
                    if member == "method" and name == "getOrdinal" and desc == "()I" and aname == "Code":
                        code = data[pos + 14:pos + 14 + u4(pos + 10)]
                        if len(code) == 2 and 0x02 <= code[0] <= 0x08 and code[1] == 0xac:
                            return code[0] - 3
                        if len(code) == 3 and code[0] == 0x10 and code[2] == 0xac:
                            return struct.unpack(">b", code[1:2])[0]
                        if len(code) == 4 and code[0] == 0x11 and code[3] == 0xac:
                            return struct.unpack(">h", code[1:3])[0]
                        if len(code) == 3 and code[0] == 0x12 and code[2] == 0xac and isinstance(pool.get(code[1]), int):
                            return pool[code[1]]
                        return -1
                    pos += 6 + alen
    except (KeyError, IndexError, struct.error):
        return -1
    return -1


class War:
    """An assembled site: the exploded directory lutece:site-assembly writes under target/."""

    def __init__(self, path, env=None):
        """Reads the lutece-core version the war ships; nothing else is read until asked. env: the environment
        variables of the container (NAME -> value), the MicroProfile source of ordinal 300."""
        self.path = pathlib.Path(path)
        self.env = env or {}
        self.lib = self.path / "WEB-INF/lib"
        self.conf = self.path / "WEB-INF/conf"
        core = sorted(self.lib.glob("lutece-core-*.jar"))
        self.core_version = re.sub(r"^lutece-core-|\.jar$", "", core[0].name) if core else ""
        self._classes = None
        self._strings = None

    def v8(self):
        """Tells whether the war runs a Lutece 8 core."""
        return self.core_version[:1] == "8" or not self.core_version

    def jars(self):
        """Every jar of WEB-INF/lib."""
        return sorted(self.lib.glob("*.jar"))

    def artefacts(self):
        """(groupId, artifactId, version, jar name) of every jar carrying Maven pom.properties."""
        out = []
        for jar in self.jars():
            try:
                with zipfile.ZipFile(jar) as z:
                    for n in z.namelist():
                        if n.startswith("META-INF/maven/") and n.endswith("/pom.properties"):
                            p = dict(parse_properties(z.read(n).decode("latin-1")))
                            out.append((p.get("groupId", ""), p.get("artifactId", ""), p.get("version", ""), jar.name))
                            break
            except zipfile.BadZipFile:
                continue
        return out

    def plugins(self):
        """Plugin descriptors: name -> {file, version, pool, class}."""
        res = {}
        for f in sorted((self.path / "WEB-INF/plugins").glob("*.xml")):
            text = f.read_text(encoding="utf-8", errors="replace")
            if "<plug-in" not in text:
                continue
            field = lambda tag: (re.search(rf"<{tag}>\s*([^<]*?)\s*</{tag}>", text) or [None, ""])[1]
            res[field("name")] = {"file": f.name, "version": field("version"), "pool": field("db-pool-required"),
                                  "class": field("class")}
        return res

    def plugins_dat(self):
        """The properties of WEB-INF/plugins/plugins.dat, or None when the war has none."""
        f = self.path / "WEB-INF/plugins/plugins.dat"
        return dict(read_properties(f)) if f.exists() else None

    def _scan_jars(self):
        """Indexes class names and class-file string constants of every jar and of WEB-INF/classes."""
        classes, strings = set(), set()
        for jar in self.jars():
            try:
                with zipfile.ZipFile(jar) as z:
                    for n in z.namelist():
                        if n.endswith(".class"):
                            classes.add(n[:-6].replace("/", "."))
                            strings.update(utf8_constants(z.read(n)))
            except zipfile.BadZipFile:
                continue
        cls = self.path / "WEB-INF/classes"
        for f in cls.rglob("*.class") if cls.exists() else []:
            classes.add(str(f.relative_to(cls))[:-6].replace(os.sep, "."))
            strings.update(utf8_constants(f.read_bytes()))
        self._classes, self._strings = classes, strings

    def classes(self):
        """Every class name the war ships."""
        if self._classes is None:
            self._scan_jars()
        return self._classes

    def strings(self):
        """Every string constant of the classes the war ships."""
        if self._strings is None:
            self._scan_jars()
        return self._strings

    def bean_names(self):
        """CDI bean name -> sorted (class, jar) of the plain named beans of the jars and of WEB-INF/classes."""
        names = {}
        for jar in self.jars():
            try:
                with zipfile.ZipFile(jar) as z:
                    for n in z.namelist():
                        if n.endswith(".class"):
                            bean = class_bean_name(z.read(n))
                            if bean and bean[2]:
                                names.setdefault(bean[1], set()).add((bean[0], jar.name))
            except zipfile.BadZipFile:
                continue
        cls = self.path / "WEB-INF/classes"
        for f in cls.rglob("*.class") if cls.exists() else []:
            bean = class_bean_name(f.read_bytes())
            if bean and bean[2]:
                names.setdefault(bean[1], set()).add((bean[0], "WEB-INF/classes"))
        return {k: sorted(v) for k, v in names.items()}

    def jar_sources(self):
        """Configuration shipped in jars: (ordinal, name, pairs) for microprofile-config.properties and ConfigSources."""
        out = []
        svc = "META-INF/services/org.eclipse.microprofile.config.spi.ConfigSource"
        for jar in self.jars():
            try:
                with zipfile.ZipFile(jar) as z:
                    names = z.namelist()
                    if "META-INF/microprofile-config.properties" in names:
                        pairs = parse_properties(z.read("META-INF/microprofile-config.properties").decode("latin-1"))
                        ordinal = int(dict(pairs).get("config_ordinal", 100))
                        out.append((ordinal, f"{jar.name}!microprofile-config.properties", pairs))
                    if svc in names:
                        for impl in z.read(svc).decode("utf-8", "replace").split():
                            if impl.startswith("#") or impl.startswith("fr.paris.lutece.util.Lutece"):
                                continue
                            cls = impl.replace(".", "/") + ".class"
                            ordinal = class_ordinal(z.read(cls)) if cls in names else -1
                            pairs = []
                            for n in names:
                                if "/" not in n and n.endswith(".properties"):
                                    pairs += parse_properties(z.read(n).decode("latin-1"))
                            out.append((ordinal, f"{jar.name}!{impl}", pairs))
            except zipfile.BadZipFile:
                continue
        mp = self.path / "WEB-INF/classes/META-INF/microprofile-config.properties"
        if mp.exists():
            out.append((100, "WEB-INF/classes/META-INF/microprofile-config.properties", read_properties(mp)))
        return out

    def conf_files(self, directory):
        """The .properties files of one conf directory, non-recursive."""
        d = self.conf / directory if directory else self.conf
        return sorted(p for p in d.glob("*.properties")) if d.is_dir() else []

    def sources(self):
        """The configuration sources, lowest priority first: (ordinal, name, ordered list of (file, pairs))."""
        root = [(f"WEB-INF/conf/{n}.properties", read_properties(self.conf / f"{n}.properties"))
                for n in ROOT_FILES if (self.conf / f"{n}.properties").exists()]
        rel = lambda p: str(p.relative_to(self.path))
        if not self.v8():
            files = root + [(rel(p), read_properties(p)) for d in ("plugins", "themes", "override", "override/plugins")
                            for p in self.conf_files(d)]
            return [(100, "LuteceConfigSource", files)]
        base = sorted(self.conf_files("plugins") + self.conf_files("themes"), key=lambda p: properties_precedence(rel(p)))
        over = sorted(self.conf_files("override") + self.conf_files("override/plugins"), key=lambda p: properties_precedence(rel(p)))
        out = [(o, n, [(n, p)]) for o, n, p in self.jar_sources()]
        out.append((150, "LuteceConfigSource", root + [(rel(p), read_properties(p)) for p in base]))
        out.append((250, "LuteceOverrideConfigSource", [(rel(p), read_properties(p)) for p in over]))
        if self.env:
            keys = {k for _, _, files in out for _, pairs in files for k, _ in pairs}
            mapped = []
            for k in sorted(keys):
                for name in (k, re.sub(r"[^A-Za-z0-9]", "_", k), re.sub(r"[^A-Za-z0-9]", "_", k).upper()):
                    if name in self.env:
                        mapped.append((k, self.env[name]))
                        break
            out.append((300, "environment", [("environment", mapped)]))
        return sorted(out, key=lambda s: s[0])

    def effective(self, profile=""):
        """key -> (value, origin file) as MicroProfile Config resolves it; a masked key has the value None."""
        resolved = {}
        for ordinal, name, files in self.sources():
            merged = {}
            for fname, pairs in files:
                for k, v in pairs:
                    merged[k] = (v, fname)
            plain = {k: v for k, v in merged.items() if not k.startswith("%")}
            if profile:
                pre = f"%{profile}."
                plain.update({k[len(pre):]: v for k, v in merged.items() if k.startswith(pre)})
            for k, (v, fname) in plain.items():
                resolved[k] = (v if v != "" else None, fname, ordinal)
        return {k: (v, f) for k, (v, f, _) in resolved.items()}

    def profiles(self):
        """Every MicroProfile profile name a key of the war's configuration names."""
        names = set()
        for _, _, files in self.sources():
            for _, pairs in files:
                names.update(k[1:].split(".", 1)[0] for k, _ in pairs if k.startswith("%") and "." in k)
        return sorted(names)

    def unknown_sources(self):
        """ConfigSources shipped in jars whose ordinal this tool does not know."""
        return [name for ordinal, name, _ in self.sources() if ordinal < 0]


class Site:
    """The sources of a site: its pom and its webapp overlay."""

    def __init__(self, path):
        """Parses the pom; the webapp is read when a check asks."""
        self.path = pathlib.Path(path)
        self.webapp = self.path / "webapp"
        self.pom = ET.parse(self.path / "pom.xml").getroot()

    def find(self, xpath):
        """Elements of the pom matching an xpath written with the m: prefix."""
        return self.pom.findall(xpath, POM_NS)

    def text(self, el, tag):
        """Text of a child element of the pom, or an empty string."""
        return child_text(el, tag)

    def dependencies(self):
        """The direct dependencies: dicts of groupId, artifactId, version, type, scope."""
        return [{t: self.text(d, t) for t in ("groupId", "artifactId", "version", "type", "scope")}
                for d in self.find("m:dependencies/m:dependency")]

    def profile_dependencies(self):
        """The dependencies declared inside the Maven profiles: (profile id, dict of groupId, artifactId, version, type, scope)."""
        return [(self.text(p, "id"), {t: self.text(d, t) for t in ("groupId", "artifactId", "version", "type", "scope")})
                for p in self.find("m:profiles/m:profile") for d in p.findall("m:dependencies/m:dependency", POM_NS)]

    def managed_imports(self):
        """The poms imported in dependencyManagement."""
        return [{t: self.text(d, t) for t in ("groupId", "artifactId", "version")}
                for d in self.find("m:dependencyManagement/m:dependencies/m:dependency")
                if self.text(d, "scope") == "import"]

    def parent(self):
        """(artifactId, version) of the parent pom."""
        p = self.pom.find("m:parent", POM_NS)
        return (self.text(p, "artifactId"), self.text(p, "version")) if p is not None else ("", "")

    def properties(self):
        """The properties of the pom."""
        return pom_properties(self.pom)

    def files(self, sub=""):
        """Every file of the webapp overlay (or of one of its sub-directories), relative to webapp/."""
        base = self.webapp / sub if sub else self.webapp
        return sorted(str(p.relative_to(self.webapp)) for p in base.rglob("*") if p.is_file()) if base.exists() else []


def child_text(el, tag):
    """Text of a child element of a pom node, or an empty string."""
    child = el.find(f"m:{tag}", POM_NS)
    return (child.text or "").strip() if child is not None else ""


def pom_properties(root):
    """The properties of a pom node."""
    node = root.find("m:properties", POM_NS)
    return {c.tag.split("}")[1]: (c.text or "").strip() for c in node} if node is not None else {}


def version_key(v):
    """A sortable key for a Maven version: numeric parts, then a qualifier rank below the release."""
    m = re.match(r"(\d+(?:\.\d+)*)(.*)", v)
    nums = tuple(int(x) for x in m.group(1).split(".")) if m else (0,)
    rest = (m.group(2) if m else v).lower()
    rank = 0 if not rest else (-1 if "snapshot" in rest else -2)
    return nums + (0,) * (4 - len(nums)), rank, rest


def bom_versions(pom_path):
    """artifactId -> (version, type) managed by a lutece-bom pom, properties resolved."""
    root = ET.parse(pom_path).getroot()
    props = pom_properties(root)
    out = {}
    for d in root.findall("m:dependencyManagement/m:dependencies/m:dependency", POM_NS):
        v = child_text(d, "version")
        v = props.get(v[2:-1], v) if v.startswith("${") else v
        out[child_text(d, "artifactId")] = (v, child_text(d, "type") or "jar")
    return out


def m2_pom(m2, g, a, v):
    """Path of an artefact's pom in a local Maven repository."""
    return pathlib.Path(m2) / g.replace(".", "/") / a / v / f"{a}-{v}.pom"


def pom_managed(pom, m2, props):
    """artifactIds a pom manages, the BOMs it imports followed through the local Maven repository with the properties
    given; None when an imported BOM is not there."""
    managed = set()
    for d in pom.findall("m:dependencyManagement/m:dependencies/m:dependency", POM_NS):
        if child_text(d, "scope") != "import":
            managed.add(child_text(d, "artifactId"))
            continue
        g, a = child_text(d, "groupId"), child_text(d, "artifactId")
        v = re.sub(r"\$\{([^}]+)\}", lambda m: props.get(m.group(1), m.group(0)), child_text(d, "version"))
        f = m2_pom(m2, g, a, v)
        if not f.is_file():
            return None
        bom = ET.parse(f).getroot()
        inner = pom_managed(bom, m2, pom_properties(bom))
        if inner is None:
            return None
        managed |= inner
    return managed


def parent_managed(pom_path, m2):
    """artifactIds the parent chain of a pom manages, with the BOMs it imports, read from the local Maven repository;
    None when a parent of the chain or a BOM it imports is not there."""
    managed, pom, chain = set(), ET.parse(pom_path).getroot(), []
    while (parent := pom.find("m:parent", POM_NS)) is not None:
        g, a, v = (child_text(parent, t) for t in ("groupId", "artifactId", "version"))
        f = m2_pom(m2, g, a, v)
        if not f.is_file():
            return None
        pom = ET.parse(f).getroot()
        chain.append(pom)
    props = {}
    for pom in reversed(chain):
        props.update(pom_properties(pom))
    for pom in chain:
        inner = pom_managed(pom, m2, props)
        if inner is None:
            return None
        managed |= inner
    return managed


def latest_local_bom(m2):
    """The newest lutece-bom 8 pom found in a local Maven repository, or None."""
    base = pathlib.Path(m2) / "fr/paris/lutece/starters/lutece-bom"
    poms = [p for p in base.glob("8.*/lutece-bom-8*.pom") if not re.search(r"-\d{8}\.\d{6}-\d+\.pom$", p.name)]
    return max(poms, key=lambda p: version_key(p.parent.name)) if poms else None


def floor_parent():
    """The lowest site parent lutecepowers supports: V8_FLOOR_SITE_PARENT when pinned, else the latest released
    lutece-site-pom 8.x (latest-lutece.py, as tools/v8-floor.conf reads it)."""
    if os.environ.get("V8_FLOOR_SITE_PARENT"):
        return os.environ["V8_FLOOR_SITE_PARENT"]
    r = subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("latest-lutece.py")), "release",
                        "fr.paris.lutece.tools:lutece-site-pom"], capture_output=True, encoding="utf-8", errors="replace")
    return r.stdout.strip().split(":")[2] if r.stdout.count(":") >= 2 else "8.0.0"


def check_pom(site, bom, out, m2=None):
    """SI01-SI09: the pom of a v8 site against the layer model (parent, BOM, starter, versions)."""
    aid, ver = site.parent()
    floor = floor_parent()
    if aid != "lutece-site-pom" or version_key(ver) < version_key(floor):
        out.add("FAIL", "SI01", f"pom.xml: parent {aid} {ver}; a v8 site has lutece-site-pom {floor} or later (the latest released 8.x)")
    else:
        out.passed("SI01", f"parent lutece-site-pom {ver}")
    boms = [i for i in site.managed_imports() if i["artifactId"] == "lutece-bom"]
    if len(boms) != 1:
        out.add("FAIL", "SI02", f"pom.xml: {len(boms)} lutece-bom import(s); a v8 site imports lutece-bom once (scope import, type pom)")
    else:
        starters = [d for d in site.dependencies() if d["artifactId"].endswith("-starter")]
        other = [d for d in starters if d["version"] != boms[0]["version"]]
        if other:
            out.add("WARN", "SI02", "pom.xml: lutece-bom " + boms[0]["version"] + " but " + ", ".join(f"{d['artifactId']} {d['version']}" for d in other)
                    + ": the BOM wins over the starter's own versions, keep both on the same version")
        else:
            out.passed("SI02", f"lutece-bom {boms[0]['version']} imported once")
    managed = bom_versions(bom) if bom else {}
    for d in site.dependencies():
        a, v, t = d["artifactId"], d["version"], d["type"] or "jar"
        if a == "lutece-core":
            out.add("WARN", "SI03", "pom.xml: lutece-core declared; the starter brings the core the BOM manages")
        if a in managed and v:
            out.add("WARN", "SI04", f"pom.xml: {a} {v} while lutece-bom manages it ({managed[a][0]}): drop the version")
        if a in managed and t != managed[a][1]:
            out.add("FAIL", "SI05", f"pom.xml: {a} declared as type {t}, lutece-bom manages it as {managed[a][1]}: the version is not found")
        if v and v[0] in "[(":
            out.add("WARN", "SI07", f"pom.xml: {a} {v}: a range; a v8 site pins what the BOM does not manage")
    inherited = parent_managed(site.path / "pom.xml", m2) if m2 else None
    for where, d in [("", d) for d in site.dependencies()] + [(f" (profile {i})", d) for i, d in site.profile_dependencies()]:
        a = d["artifactId"]
        if not managed or d["version"] or a in managed or (inherited is not None and a in inherited):
            continue
        if inherited is not None or d["scope"] not in ("provided", "test"):
            out.add("FAIL", "SI06", f"pom.xml{where}: {a} has no version and neither lutece-bom nor the parent poms manage it: the pom does not load")
        else:
            out.add("WARN", "SI06", f"pom.xml{where}: {a} has no version and lutece-bom does not manage it; the parent poms are not in the local repository to tell")
    dead = [k for k in site.properties() if re.fullmatch(r"lutece\.[\w.\-]+\.version", k)]
    if dead:
        out.add("WARN", "SI08", "pom.xml: " + ", ".join(dead) + ": a lutece.*.version property of the site does not change the version the imported BOM manages")
    profiles = [p for p in site.find("m:profiles/m:profile") if p.find(".//m:defaultConfDirectory", POM_NS) is not None]
    confs = [d.name for d in (site.path / "src/conf").iterdir() if d.is_dir() and d.name != "default"] if (site.path / "src/conf").is_dir() else []
    if profiles or confs:
        out.add("FAIL", "SI09", "src/conf/" + ",".join(confs or ["?"]) + ": lutece-site-pom copies no per-environment conf directory; move each value to a MicroProfile profile key (%<profile>.key) in conf/override")


def check_build(site, out):
    """SI10-SI12: what site-assembly silently drops (Java, microprofile-config.properties, SQL out of Liquibase)."""
    if (site.path / "src/java").is_dir() and any((site.path / "src/java").rglob("*.java")):
        out.add("FAIL", "SI10", "src/java: the lutece-site lifecycle compiles no Java; move the code to a plugin or module")
    excluded = [f for f in site.files("WEB-INF/classes") if re.search(r"fr/paris/lutece/.*/(business|web|service|util|utils)/", f)]
    if excluded:
        out.add("FAIL", "SI10", f"webapp/{excluded[0]}: the war excludes fr/paris/lutece/**/(business|web|service|util|utils)/** ({len(excluded)} files)")
    if (site.webapp / "WEB-INF/classes/META-INF/microprofile-config.properties").exists():
        out.add("FAIL", "SI11", "webapp/WEB-INF/classes/META-INF/microprofile-config.properties: site-assembly deletes and rewrites this file; put the keys in WEB-INF/conf/override")
    for f in sorted((site.path / "src/sql").rglob("*.sql")) if (site.path / "src/sql").is_dir() else []:
        rel = str(f.relative_to(site.path / "src"))
        if f.stat().st_size == 0:
            continue
        first = f.read_text(encoding="utf-8", errors="replace").lstrip("﻿").split("\n", 1)[0].strip()
        if not sql_paths.managed(rel):
            out.add("FAIL", "SI12", f"src/{rel}: path SqlPathInfo does not parse, plugin-liquibase never runs it (sql/plugins/<p>/plugin|core|upgrade, sql/themes/<t>/...)")
        elif not re.match(r"--\s*liquibase formatted sql", first):
            out.add("FAIL", "SI12", f"src/{rel}: first line is not `-- liquibase formatted sql`, the script is never run")


SQL_COMPONENT = re.compile(r"sql/(?:plugins/(?P<plugin>[\w\-]+)(?:/modules/(?P<module>\w+))?/(?P<kind>core|plugin|upgrades?)"
                           r"|themes/(?P<theme>\w+)(?:/(?P<tkind>upgrade))?)/[^/]+\.sql")
SQL_DST = re.compile(r"[\-_](" + sql_paths.VERSION + r")\.sql$")
CORE_UPGRADE = re.compile(r"sql/upgrade/update_db_lutece_core-" + sql_paths.VERSION + "-(" + sql_paths.VERSION + r")\.sql")


def war_sql(war):
    """The Liquibase-managed SQL files of an assembled site, path from sql/ -> file. A Lutece 8 war: only
    WEB-INF/classes/sql, the classpath plugin-liquibase searches. An older one, whose database ant built from
    WEB-INF/sql: both, WEB-INF/classes winning."""
    res = {}
    bases = [war.path / "WEB-INF", war.path / "WEB-INF/classes"]
    if war.v8() and (bases[1] / "sql").is_dir():
        bases = bases[1:]
    for base in bases:
        for f in sorted((base / "sql").rglob("*.sql")) if (base / "sql").is_dir() else []:
            rel = str(f.relative_to(base)).replace(os.sep, "/")
            if sql_paths.managed(rel):
                res[rel] = f
    return res


def created_tables(war):
    """Tables each plugin component of a war creates in its create scripts: component name -> set of tables."""
    res = {}
    for rel, f in war_sql(war).items():
        m = SQL_COMPONENT.fullmatch(rel)
        if m and m.group("plugin") and m.group("kind") == "plugin" and f.name.startswith("create"):
            name = m.group("plugin") + ("-" + m.group("module") if m.group("module") else "")
            text = f.read_text(encoding="utf-8", errors="replace")
            res.setdefault(name, set()).update(t.lower() for t in re.findall(r"CREATE TABLE\s+(?:IF NOT EXISTS\s+)?`?(\w+)", text, re.I))
    return res


def renamed_components(before, after):
    """Components of the after war the before war does not declare whose create scripts create tables a component of
    the before war created: new name -> (former name, shared tables). A former name the after war still declares is
    kept too: the tables are shared."""
    declared = set(before.plugins())
    old, new = created_tables(before), created_tables(after)
    res = {}
    for name, tables in new.items():
        if name in declared:
            continue
        for former, had in sorted(old.items()):
            if former != name and tables & had:
                res[name] = (former, sorted(tables & had))
                break
    return res


def takeover_scripts(before, after):
    """The scripts plugin-liquibase runs when the after war takes over the database of the before war, by the rules of
    TestIncludeAllFilter: the core upgrades past the before core, the create/init scripts of a component the before
    war did not ship, the upgrades of a shipped component past its before version. Returns (core, components), each a
    list of (path, file)."""
    shipped = {n: d["version"] for n, d in before.plugins().items()}
    shipped.update({new: shipped[old] for new, (old, _) in renamed_components(before, after).items() if shipped.get(old)})
    themes = {m.group("theme") for m in map(SQL_COMPONENT.fullmatch, war_sql(before)) if m and m.group("theme")}
    core_from = version_key(before.core_version)[0]
    core, components = [], []
    for rel, f in sorted(war_sql(after).items()):
        m = CORE_UPGRADE.fullmatch(rel)
        if m:
            if version_key(m.group(1))[0] > core_from:
                core.append((rel, f))
            continue
        m = SQL_COMPONENT.fullmatch(rel)
        if not m:
            continue
        if m.group("theme"):
            known, since, update = before.v8() and m.group("theme") in themes, None, bool(m.group("tkind"))
        else:
            name = m.group("plugin") + ("-" + m.group("module") if m.group("module") else "")
            known, since, update = name in shipped, shipped.get(name), m.group("kind").startswith("upgrade")
        dst = SQL_DST.search(rel)
        if (not update and not known) or (update and known and (since is None or not dst
                                                                or version_key(dst.group(1))[0] > version_key(since)[0])):
            components.append((rel, f))
    return core, components


DS_INSERT = re.compile(r"INSERT INTO core_datastore[^;]*?VALUES\s*\(\s*'([^']+)'", re.I)
DS_DELETE = re.compile(r"DELETE FROM core_datastore WHERE entity_key\s*(=|LIKE)\s*'([^']+)'", re.I)


def like(pattern):
    """The regular expression of a SQL LIKE pattern."""
    return re.compile("".join(".*" if c == "%" else "." if c == "_" else re.escape(c) for c in pattern))


def check_fresh_datastore(war, out):
    """SI89: an install script of the war (a theme, a site, a pack) inserting a datastore key the core's own install
    already inserts, with no DELETE before it: on a new database the core goes first and the insert hits a duplicate key."""
    sql = war.path / "WEB-INF/classes/sql"
    core = sql / "init_db_lutece_core.sql"
    if not core.is_file():
        return
    inserted = set(DS_INSERT.findall(core.read_text(encoding="utf-8", errors="replace")))
    for f in sorted(sql.rglob("init_*.sql")):
        if f == core:
            continue
        text = f.read_text(encoding="utf-8", errors="replace")
        dels = [(op.upper(), k) for op, k in DS_DELETE.findall(text)]
        keys = [m.group(1) for m in DS_INSERT.finditer(text) if not re.match(r"[^;]*ON\s+DUPLICATE\s+KEY", text[m.start():], re.I)]
        dup = sorted({k for k in keys if k in inserted and not any(k == d if op == "=" else like(d).fullmatch(k) for op, d in dels)})
        if dup:
            out.add("FAIL", "SI89", f"{f.relative_to(war.path)}: inserts " + ", ".join(dup) + " that the core install already inserts: "
                    "a new database fails on the duplicate key; DELETE the key first, or UPDATE it")


def duplicate_keys(before, after):
    """Datastore keys a component script of the takeover inserts without deleting them first while a core upgrade of
    the takeover inserts them too: once the core goes first, the insert hits a duplicate key. Script path -> keys."""
    core, components = takeover_scripts(before, after)
    inserted = {k for _, f in core for k in DS_INSERT.findall(f.read_text(encoding="utf-8", errors="replace"))}
    res = {}
    for rel, f in components:
        text = f.read_text(encoding="utf-8", errors="replace")
        dels = [(op.upper(), k) for op, k in DS_DELETE.findall(text)]
        bare = [k for k in DS_INSERT.findall(text) if not any(k == d if op == "=" else like(d).fullmatch(k) for op, d in dels)]
        dup = sorted(set(bare) & inserted)
        if dup:
            res[rel] = dup
    return res


def check_takeover(before, after, out):
    """SI13: on the database of the before war, a component script that inserts a datastore key the core upgrade
    inserts too, without deleting it first, hits a duplicate key; a script using a table the core upgrade drops fails
    once it does."""
    core, components = takeover_scripts(before, after)
    if not core or not components:
        return
    created, dropped = set(), set()
    for _, f in core:
        text = f.read_text(encoding="utf-8", errors="replace")
        created |= {t.lower() for t in re.findall(r"CREATE TABLE\s+(?:IF NOT EXISTS\s+)?`?(\w+)", text, re.I)}
        dropped |= {t.lower() for t in re.findall(r"DROP TABLE\s+(?:IF EXISTS\s+)?`?(\w+)", text, re.I)}
    gone = dropped - created
    first, broken = 0, 0
    for rel, keys in sorted(duplicate_keys(before, after).items()):
        first += 1
        out.add("WARN", "SI13", f"{rel}: inserts {', '.join(keys)} without deleting it first, a key the core upgrade inserts: a duplicate key once the core is upgraded; the takeover deletes it before the components (the script needs the DELETE)")
    for rel, f in components:
        text = f.read_text(encoding="utf-8", errors="replace")
        tables = {t.lower() for t in re.findall(r"\b(core_\w+)\b", text, re.I)}
        if tables & gone:
            broken += 1
            out.add("FAIL", "SI13", f"{rel}: uses {', '.join(sorted(tables & gone))} that the core upgrade drops: it belongs to the v7 schema; apply it to the database before the takeover and record its version, or it fails once the core is upgraded")
    if not first and not broken:
        out.passed("SI13", f"{len(components)} component script(s) of the takeover need nothing from the {len(core)} core upgrade(s)")


def check_renames(before, after, out):
    """SI14: a component the before war does not declare whose create script creates tables of the before site (a
    renamed plugin): Liquibase installs it as new, so its upgrades never run, and a create script no precondition
    guards drops the tables."""
    declared = set(after.plugins())
    for new, (old, tables) in sorted(renamed_components(before, after).items()):
        if old in declared:
            out.add("FAIL", "SI14", f"{new}: its create script creates {', '.join(tables)} that {old}, still shipped, already created: installing {new} runs it on them")
        else:
            out.add("WARN", "SI14", f"{new}: renamed from {old} (its create script re-creates {', '.join(tables)}): on the takeover the keys and the version of {old} move to {new} (site_check.py takeover), or Liquibase installs it as new and never runs its upgrades")


MAX_VERSION = str(2 ** 31 - 1)


def upsert(key, value):
    """The MySQL / MariaDB statement that sets one datastore key."""
    return f"INSERT INTO core_datastore (entity_key, entity_value) VALUES ('{key}', '{value}') ON DUPLICATE KEY UPDATE entity_value = '{value}';"


def takeover_plan(before, after):
    """The two SQL scripts of the takeover of the before site's database by the after war (reference/database.md §1),
    each played on the stopped database before a normal start: the first lets only the core upgrades run (every
    component marked newer than any script), the second sets each component to what the before site had installed,
    moves the keys of a renamed component to its new name and removes the version of a new one so that its create
    and init scripts run. Returns (core_sql, components_sql)."""
    names = sorted(n for n in after.plugins() if n != "core")
    themes = sorted({m.group("theme") for m in map(SQL_COMPONENT.fullmatch, war_sql(after)) if m and m.group("theme")})
    had = {n: d["version"] for n, d in before.plugins().items()}
    renamed = renamed_components(before, after)
    config = before.effective() if before.v8() else {}
    core = ["-- takeover 1/2 (MySQL / MariaDB): only the core upgrades run",
            upsert("core.plugins.status.core.version", before.core_version)]
    core += [upsert(f"core.plugins.status.{p}.version", MAX_VERSION) for p in names]
    core += [upsert(f"core.theme.status.{t}.version", MAX_VERSION) for t in themes]
    comps = ["-- takeover 2/2 (MySQL / MariaDB): each component from what the before site had installed"]
    for rel, keys in sorted(duplicate_keys(before, after).items()):
        comps += [f"-- {rel} inserts these keys without the DELETE its other keys have, and the core upgrade inserted them"]
        comps += [f"DELETE FROM core_datastore WHERE entity_key = '{k}';" for k in keys]
    for p in names:
        key = f"core.plugins.status.{p}.version"
        if p in had:
            comps.append(upsert(key, had[p]))
        elif p in renamed:
            old, tables = renamed[p]
            a, b = f"core.plugins.status.{old}.", f"core.plugins.status.{p}."
            comps += [f"-- {p}: renamed from {old}, its create script re-creates {', '.join(tables)}: the keys of {old} win",
                      f"DELETE FROM core_datastore WHERE entity_key LIKE '%{b}%' AND REPLACE(entity_key, '{b}', '{a}') IN (SELECT entity_key FROM (SELECT entity_key FROM core_datastore WHERE entity_key LIKE '%{a}%') AS former);",
                      f"UPDATE core_datastore SET entity_key = REPLACE(entity_key, '{a}', '{b}') WHERE entity_key LIKE '%{a}%';",
                      f"UPDATE core_admin_right SET plugin_name = '{p}' WHERE plugin_name = '{old}';"]
            if had.get(old):
                comps.append(upsert(key, had[old]))
        else:
            comps += [f"-- {p}: new to this database, its create and init scripts run", f"DELETE FROM core_datastore WHERE entity_key = '{key}';"]
    for t in themes:
        key = f"core.theme.status.{t}.version"
        version = (config.get(f"themes.{t}.version") or (None, None))[0]
        if version:
            comps.append(upsert(key, version))
        elif before.v8():
            comps.append(f"-- theme {t}: version of the before site unknown, left as the core pass recorded it")
        else:
            comps += [f"-- theme {t}: a v7 database records no theme version, its create and init scripts run", f"DELETE FROM core_datastore WHERE entity_key = '{key}';"]
    return "\n".join(core) + "\n", "\n".join(comps) + "\n"


READ_PROPERTIES = re.compile(r"WEB-INF/conf/(?:[^/]+|plugins/[^/]+|themes/[^/]+|override/[^/]+|override/plugins/[^/]+)\.properties")


def check_unread_properties(site, out):
    """SI32: properties files of the overlay (webapp/ and every src/conf/<env>/) in a place the core reads nothing."""
    roots = [site.webapp] + ([d for d in (site.path / "src/conf").iterdir() if d.is_dir()] if (site.path / "src/conf").is_dir() else [])
    for root in roots:
        for f in sorted(root.rglob("*.properties")) if root.exists() else []:
            rel = str(f.relative_to(root))
            if not rel.startswith("WEB-INF/") or rel.startswith("WEB-INF/classes/") or READ_PROPERTIES.fullmatch(rel):
                continue
            out.add("WARN", "SI32", f"{f.relative_to(site.path)}: the core reads no properties file there (only WEB-INF/conf/, conf/plugins/, conf/themes/, conf/override/, conf/override/plugins/): its keys apply nowhere")


def check_conf(site, war, out):
    """SI20-SI29: the configuration a v8 core reads (Spring, logging, database, override keys, profiles)."""
    check_unread_properties(site, out)
    for f in site.files("WEB-INF/conf"):
        if f.endswith("_context.xml"):
            text = re.sub(r"<!--.*?-->", "", (site.webapp / f).read_text(encoding="utf-8", errors="replace"), flags=re.S)
            sev = "FAIL" if "<bean" in text else "WARN"
            out.add(sev, "SI20", f"webapp/{f}: a v8 core reads no Spring context; a bean value becomes a key, a replaced bean an @Alternative in a plugin")
        if f.endswith("log.properties"):
            out.add("WARN", "SI21", f"webapp/{f}: v8 reads no log.properties; logging is log4j2 (WEB-INF/conf/override/log4j2*.xml) or the container's")
    db = site.webapp / "WEB-INF/conf/db.properties"
    if db.exists():
        props = dict(read_properties(db))
        dat = dict(read_properties(site.webapp / "WEB-INF/plugins/plugins.dat")) if (site.webapp / "WEB-INF/plugins/plugins.dat").exists() else {}
        pools = {"portal"} | {v for k, v in dat.items() if k.endswith(".pool")}
        server = site.path / "src/main/liberty/config/server.xml"
        jndi = set(re.findall(r'jndiName="([^"]+)"', server.read_text(encoding="utf-8", errors="replace"))) if server.exists() else set()
        for pool in sorted(pools):
            service = props.get(f"{pool}.poolservice", "")
            if "C3p0" in service or "c3p0" in service:
                out.add("FAIL", "SI22", f"webapp/WEB-INF/conf/db.properties: {pool}.poolservice {service}: C3p0 is gone in v8 (LuteceInitException)")
            elif service and "ManagedConnectionService" not in service:
                out.add("WARN", "SI22", f"webapp/WEB-INF/conf/db.properties: {pool}.poolservice {service}; the container datasource is ManagedConnectionService + {pool}.ds")
            ds = props.get(f"{pool}.ds", "")
            if "ManagedConnectionService" in service and not ds:
                out.add("FAIL", "SI23", f"webapp/WEB-INF/conf/db.properties: pool {pool} has no {pool}.ds (the JNDI name of its datasource)")
            elif ds and server.exists() and ds not in jndi:
                out.add("FAIL", "SI23", f"src/main/liberty/config/server.xml: no <dataSource jndiName=\"{ds}\"> for pool {pool}")
            if props.get(f"{pool}.password"):
                out.add("WARN", "SI24", f"webapp/WEB-INF/conf/db.properties: {pool}.password in clear; the datasource credentials belong to server.xml variables or the environment")
    if war:
        check_driver(site, war, out)
        check_server_variables(site, war, out)
        check_override_keys(site, war, out)
        check_class_values(war, out)
        check_bean_names(war, out)
        check_fresh_datastore(war, out)
        check_profiles(site, war, out)


def check_driver(site, war, out):
    """SI25: the JDBC driver the Liberty configuration loads is a jar of the war."""
    server = site.path / "src/main/liberty/config/server.xml"
    if not server.exists():
        return
    names = [j.name for j in war.jars()]
    for inc in re.findall(r'<fileset[^>]*includes="([^"]+)"', server.read_text(encoding="utf-8", errors="replace")):
        for pattern in inc.split(","):
            rx = re.compile(pattern.strip().replace(".", r"\.").replace("*", ".*") + "$")
            if not any(rx.match(n) for n in names):
                out.add("FAIL", "SI25", f"src/main/liberty/config/server.xml: fileset {pattern.strip()} matches no jar of the war (drivers shipped: " +
                        ", ".join(n for n in names if re.search(r"mariadb|mysql|postgres|ojdbc", n)) + ")")


def check_server_variables(site, war, out):
    """SI31: a Liberty <variable> named like a Lutece key wins over every properties file (ordinal 500)."""
    server = site.path / "src/main/liberty/config/server.xml"
    if not server.exists():
        return
    keys = {k for _, _, files in war.sources() for _, pairs in files for k, _ in pairs}
    for name in re.findall(r'<variable\s+[^>]*name="([^"]+)"', server.read_text(encoding="utf-8", errors="replace")):
        if name in keys:
            out.add("WARN", "SI31", f"src/main/liberty/config/server.xml: variable {name} is also a key of the site configuration; at ordinal 500 it wins over every .properties file")


def check_override_keys(site, war, out):
    """SI26-SI27: the keys the site overrides, against the files of the same source and the code that reads them."""
    over = site.files("WEB-INF/conf/override")
    seen = {}
    for f in [x for x in over if OVERRIDE_FILE.fullmatch(x)]:
        for k, v in read_properties(site.webapp / f):
            seen.setdefault(k, []).append((f, v))
    for k, defs in sorted(seen.items()):
        values = {v for _, v in defs}
        if len({f for f, _ in defs}) > 1 and len(values) > 1:
            winner = max((f for f, _ in defs), key=properties_precedence)
            out.add("WARN", "SI26", f"{k} set to different values in " + ", ".join(sorted({f for f, _ in defs})) +
                    f": in v8 the last file loaded wins ({winner}); keep one definition")
    defaults = set()
    for ordinal, _, files in war.sources():
        if ordinal < 250:
            for _, pairs in files:
                defaults.update(k for k, _ in pairs)
    strings = war.strings()
    prefixes = {s for s in strings if s.endswith(".") and 4 <= len(s) and KEY_LIKE.fullmatch(s[:-1])}
    defaults_values = {}
    for ordinal, _, files in war.sources():
        if ordinal < 250:
            for _, pairs in files:
                defaults_values.update(dict(pairs))
    unread = {}
    for k in sorted(seen):
        bare = k.split(".", 1)[1] if k.startswith("%") and "." in k else k
        if bare in defaults or bare in strings:
            continue
        parts = bare.split(".")
        if any(".".join(parts[:i]) + "." in prefixes for i in range(1, len(parts))):
            continue
        renamed = sorted(c for c in defaults | {s for s in strings if KEY_LIKE.fullmatch(s)} if c.endswith("." + bare))
        value = next((v for f, v in seen[k]), "")
        if renamed:
            lost = [c for c in renamed if defaults_values.get(c, value) != value]
            sev = "FAIL" if lost else "WARN"
            out.add(sev, "SI27", f"{k}: read by nothing, the war reads {', '.join(renamed)}: a renamed key" +
                    (f"; the site's value is lost (the default of {lost[0]} applies instead): carry it under the new name" if lost else "; same value as its default"))
            continue
        unread.setdefault(parts[0], []).append(k)
    for head, keys in sorted(unread.items()):
        if len(keys) == 1:
            out.add("WARN", "SI27", f"{keys[0]}: no default of the core or of a plugin declares it and no class of the war names it; a key read by nothing (a typo, a renamed key, a removed plugin)")
        else:
            out.add("WARN", "SI27", f"{len(keys)} keys {head}.* read by nothing (no default declares them, no class of the war names them: a plugin the war no longer ships, or renamed keys): " + ", ".join(keys[:4]) + (", …" if len(keys) > 4 else ""))


def check_bean_names(war, out):
    """SI88: two plain CDI beans of the war under one name stop the deployment (WELD-001414, ambiguous bean name)."""
    for name, beans in sorted(war.bean_names().items()):
        if len({c for c, _ in beans}) > 1:
            out.add("FAIL", "SI88", f"CDI bean name {name} carried by " + ", ".join(f"{c} ({j})" for c, j in beans) +
                    ": the site does not deploy (WELD-001414); give the bean a @Named value prefixed with its plugin "
                    "(myPluginCommentJspBean) and call that name from its JSPs")


def check_class_values(war, out):
    """SI28: every configuration value that names a class names one the war ships."""
    classes = war.classes()
    missing = {}
    for profile in [""] + war.profiles():
        for k, (v, origin) in sorted(war.effective(profile).items()):
            for token in re.split(r"[\s,;]+", v or ""):
                if CLASS_VALUE.fullmatch(token) and token.split(".")[0] in ("fr", "org", "com", "net", "io") and token not in classes \
                        and not token.startswith(JDK_PACKAGES):
                    missing.setdefault((k, token, origin), []).append(profile or "no profile")
    for (k, token, origin), where in sorted(missing.items()):
        own = "override" in origin or "!" in origin
        scope = "every profile" if len(where) == len(war.profiles()) + 1 else ", ".join(where)
        out.add("FAIL" if own else "WARN", "SI28", f"{k}={token} ({origin}; {scope}): no such class in the war" +
                ("" if own else "; set by the core or a plugin itself, not by the site"))


def check_secrets(site, out):
    """SI30: credentials written in the site overlay (properties and Spring contexts)."""
    secret, placeholder = SECRET_KEY, PLACEHOLDER
    for f in site.files("WEB-INF/conf"):
        path = site.webapp / f
        if f.endswith(".properties"):
            for k, v in read_properties(path):
                if secret.search(k) and not placeholder.match(v.strip()):
                    out.add("WARN", "SI30", f"webapp/{f}: {k} holds a value in the repository; a secret belongs to Vault or the environment")
        elif f.endswith(".xml"):
            text = path.read_text(encoding="utf-8", errors="replace")
            for m in re.finditer(r'<property\s+name="([^"]+)"\s+value="([^"]*)"', text):
                if secret.search(m.group(1)) and not placeholder.match(m.group(2).strip()):
                    out.add("WARN", "SI30", f"webapp/{f}: bean property {m.group(1)} holds a value in the repository; a secret belongs to Vault or the environment")


def site_profiles(pairs_by_file):
    """Profile names the keys of some override files name."""
    return sorted({k[1:].split(".", 1)[0] for pairs in pairs_by_file for k, _ in pairs if k.startswith("%") and "." in k})


def check_profiles(site, war, out):
    """SI29: profile keys of the site against the profiles its configuration sources know, and profile-like keys without %."""
    known = set(war.profiles()) | {"dev", "rec", "prod", "preprod", "integ", "recette"}
    readable = set(war.strings())
    for _, _, files in war.sources():
        for _, pairs in files:
            readable.update(k for k, _ in pairs if not k.startswith("%"))
    files = [f for f in site.files("WEB-INF/conf/override") if OVERRIDE_FILE.fullmatch(f)]
    for f in files:
        for k, _ in read_properties(site.webapp / f):
            head, _, rest = k.partition(".")
            if not k.startswith("%") and head in known and rest in readable:
                out.add("WARN", "SI29", f"webapp/{f}: {k}: {head} is a profile name without the % prefix; the key is literal and read by nothing (%{k})")
    if war.unknown_sources():
        out.add("WARN", "SI29", "ConfigSource(s) whose ordinal is computed at run time: " + ", ".join(war.unknown_sources()) +
                "; the effective configuration is only certain from a running site (the bench config dump)")
    for ordinal, name, source_files in war.sources():
        if "!" in name and ordinal >= 0 and not any(pairs for _, pairs in source_files):
            above = " above the site's conf/override (250): every key it serves replaces the site's value" if ordinal > 250 else ""
            out.add("WARN", "SI29", f"ConfigSource {name.split('!')[-1]} at ordinal {ordinal} serves values the war does not hold (a remote store){above}; list them from the running site (the bench config dump)")
    used = site_profiles(read_properties(site.webapp / f) for f in files)
    if used:
        out.add("INFO", "SI29", "profiles named by the site: " + ", ".join(used) + "; each environment must set one of them (mp.config.profile or MP_CONFIG_PROFILE)")


def check_plugins(site, war, out):
    """SI40-SI44: plugins.dat of the site against the plugin descriptors the war ships; SI43 a line still naming a
    renamed plugin by its former name, which leaves the plugin disabled."""
    desc = war.plugins()
    dat = war.plugins_dat()
    if dat is None:
        if desc:
            out.add("FAIL", "SI44", f"WEB-INF/plugins/plugins.dat: none in the war; the {len(desc)} plugins start disabled on a new database")
        return
    installed = {k[:-len(".installed")] for k, v in dat.items() if k.endswith(".installed") and v == "1"}
    pools = {k[:-len(".pool")] for k in dat if k.endswith(".pool")}
    stale = sorted(installed - set(desc) - {"core_extensions", "core"})
    renamed = {}
    for rel in war_sql(war):
        m = SQL_COMPONENT.fullmatch(rel)
        if m and m.group("plugin"):
            name = m.group("plugin") + ("-" + m.group("module") if m.group("module") else "")
            for former in stale:
                if name in desc and name not in installed and former in rel.rsplit("/", 1)[-1]:
                    renamed.setdefault(name, former)
    for n in sorted(set(desc) - installed):
        if n in renamed:
            out.add("FAIL", "SI43", f"plugins.dat: {renamed[n]}.installed=1 names the former name of {n} (its SQL files still carry it) and {n} has no line: {n} stays disabled, on a new database and on one updated from the former name; write {n}.installed=1")
        else:
            out.add("WARN", "SI40", f"plugins.dat: {n} ({desc[n]['file']}) has no {n}.installed=1: disabled on a new database")
    for n in stale:
        if n not in renamed.values():
            out.add("WARN", "SI41", f"plugins.dat: {n}.installed=1 but no descriptor of the war is named {n}: the line does nothing")
    nopool = sorted(n for n, d in desc.items() if d["pool"] == "1" and n in installed and n not in pools)
    if nopool:
        out.add("WARN", "SI42", f"plugins.dat: {len(nopool)} plugin(s) require a pool and have no <name>.pool line (the core logs a warning and uses portal): " + ", ".join(nopool))
    if not any(l.startswith("  WARN [SI4") or l.startswith("  FAIL [SI4") for l in out.lines):
        out.passed("SI40", f"plugins.dat matches the {len(desc)} plugin descriptors")


def read_text(path):
    """The text of a file, or an empty string when it is missing; any encoding is read."""
    return path.read_text(encoding="latin-1") if path.is_file() else ""


def override_text(site):
    """Every properties file of the site under WEB-INF/conf/override, concatenated, comments removed."""
    base = site.webapp / "WEB-INF/conf/override"
    files = sorted(base.rglob("*.properties")) if base.exists() else []
    return "\n".join(l for f in files for l in read_text(f).splitlines() if not l.lstrip().startswith("#"))


def war_daemons(war):
    """The daemon ids of the core and of every plugin descriptor of the war."""
    ids = set()
    for f in [war.conf / "core.xml"] + sorted((war.path / "WEB-INF/plugins").glob("*.xml")):
        text = re.sub(r"<!--.*?-->", "", read_text(f), flags=re.S)
        ids.update(re.findall(r"<daemon-id>\s*([^<\s]+)\s*</daemon-id>", text))
    return ids


def member_cache_names(member):
    """Returns the names declared under the cache section of a Hazelcast member YAML, quotes removed."""
    names, inside = [], False
    for line in member.splitlines():
        if re.match(r"^  cache:\s*$", line):
            inside = True
        elif inside and re.match(r"^ {0,2}\S", line):
            inside = False
        elif inside:
            m = re.match(r"^    (['\"]?)([^'\":#][^'\"]*?)\1\s*:", line)
            if m:
                names.append(m.group(2))
    return names


def check_cluster(site, war, out):
    """SI60-SI68: the configuration of a site set up for several replicas (sessionCache-1.0 or sessionDatabase-1.0,
    a cluster.xml or a Hazelcast dependency): HTTP session, Lutece cache, Hazelcast member and client, JVM options,
    Liberty endpoint and pools, clustered daemons, packaging, Forms index lock. Nothing is reported for a single-instance
    site."""
    cfg = site.path / "src/main/liberty/config"
    server, cluster = read_text(cfg / "server.xml"), read_text(cfg / "cluster.xml")
    liberty = server + cluster
    deps = [d["artifactId"] for d in site.dependencies()] + [d["artifactId"] for _, d in site.profile_dependencies()]
    if not (cluster or "sessionCache-1.0" in server or "sessionDatabase-1.0" in server or "hazelcast" in deps):
        return
    jars = [j.name for j in war.jars()] if war else []
    override = override_text(site)
    member, client = read_text(cfg / "hazelcast-config-api-mode.yaml"), read_text(cfg / "hazelcast-client-config-api-mode.yaml")
    jvm = read_text(cfg / "jvm.options")
    n = 0
    if "sessionDatabase-1.0" in liberty and "sessionCache-1.0" not in liberty:
        out.add("INFO", "SI60", "HTTP session in a database (sessionDatabase-1.0): the Hazelcast checks SI61, SI63, SI64 do not apply")
        hazelcast = False
    elif "sessionCache-1.0" not in liberty:
        out.add("FAIL", "SI60", "src/main/liberty/config: no sessionCache-1.0 nor sessionDatabase-1.0 feature: each replica keeps its own HTTP sessions")
        hazelcast, n = False, n + 1
    else:
        hazelcast = "hazelcast" in liberty.lower() or "hazelcast" in deps
        if hazelcast and "hazelcast" not in deps and not any(j.startswith("hazelcast-") for j in jars):
            out.add("FAIL", "SI60", "pom.xml: sessionCache-1.0 configured for Hazelcast and no hazelcast dependency: the provider is not found")
            n += 1
    if hazelcast:
        lib = re.search(r'<httpSessionCache[^>]*libraryRef="([^"]+)"', liberty)
        libdef = re.search(rf'<library[^>]*id="{lib.group(1)}"[^>]*>(.*?)</library>', liberty, re.S) if lib else None
        if not libdef or 'includes="*.jar"' not in libdef.group(1):
            out.add("FAIL", "SI61", "httpSessionCache: the session library is not every jar of the war (includes=\"*.jar\"): the members cannot migrate the partitions of the Lutece caches")
            n += 1
        if 'writeContents="GET_AND_SET_ATTRIBUTES"' not in liberty:
            out.add("FAIL", "SI61", "httpSessionCache: writeContents is not GET_AND_SET_ATTRIBUTES: a @SessionScoped bean modified in place is lost on a node switch")
            n += 1
    if "lutece.cache.jcache.cachingprovider" not in liberty and "lutece.cache.jcache.cachingprovider" not in override:
        out.add("FAIL", "SI62", "no lutece.cache.jcache.cachingprovider: the Lutece caches stay local to each replica (stale data on the others)")
        n += 1
    if hazelcast:
        caches = member_cache_names(member)
        generic = [c for c in caches if "*" in c and not c.startswith("com.ibm.ws.session.")]
        if generic:
            out.add("FAIL", "SI63", f"hazelcast-config-api-mode.yaml: member cache entry {', '.join(generic)}: it also matches the OpenLiberty session caches (SESN0307E, the application does not start on a cluster started from zero)")
            n += 1
        named = [c for c in caches if "*" not in c]
        if named:
            out.add("INFO", "SI63", f"member caches declared by name ({', '.join(named)}): this configuration replaces the Lutece one for them (lifetime, size, backups)")
        mn, cn = (re.search(r"cluster-name:\s*(\S+)", t) for t in (member, client))
        if member and client and (not mn or not cn or mn.group(1) != cn.group(1)):
            out.add("FAIL", "SI63", "Hazelcast member and client cluster-name differ: the client of the Lutece cache never connects")
            n += 1
        for text, needle, why in ((member, "hazelcast.shutdownhook.policy: GRACEFUL", "member: graceful shutdown (partitions migrated before the pod stops)"),
                                  (member, "hazelcast.shutdownhook.enabled: false", "member: JVM shutdown hook disabled (OpenLiberty closes the member after the application)"),
                                  (member, "hazelcast.cache.invalidation.batch.enabled: false", "member: immediate near-cache invalidations"),
                                  (member, "auto-increment: false", "member: fixed port"),
                                  (member, "kubernetes:", "member: Kubernetes discovery"),
                                  (client, "near-cache:", "client: near cache"),
                                  (client, "127.0.0.1:5701", "client: member of its own pod")):
            if needle not in text:
                out.add("WARN", "SI63", f"{why} missing ({needle})")
                n += 1
        if "hazelcast.jcache.provider.type=member" not in jvm:
            out.add("FAIL", "SI64", "jvm.options: no -Dhazelcast.jcache.provider.type=member: the provider of sessionCache-1.0 starts as a client and no member exists")
            n += 1
        for needle, why in (("hz.service-name", "Kubernetes service of the Hazelcast port"), ("add-opens=java.base/java.lang", "Hazelcast --add-opens")):
            if needle not in jvm:
                out.add("WARN", "SI64", f"jvm.options: {why} missing ({needle})")
                n += 1
    timeout = re.search(r'persistTimeout="(\d+)s"', server)
    if not timeout or int(timeout.group(1)) <= 60:
        out.add("WARN", "SI65", "server.xml: persistTimeout not above the 60 s keep-alive of the load balancer: a POST on a connection Liberty just closed gets a 502")
        n += 1
    for needle, why in (("<remoteIp", "no <remoteIp/> in the httpEndpoint: every user has the address of the ingress (upload DOS guard shared)"),
                        ("maxThreads=", "no bounded <executor>: the thread pool grows without limit when the replica saturates"),
                        ("maxPoolSize=", "no <connectionManager maxPoolSize> on the data source: 50 connections per replica by default")):
        if needle not in server:
            out.add("WARN", "SI65", f"server.xml: {why}")
            n += 1
    if "plugin-quartz-scheduler" not in deps and not any(j.startswith("plugin-quartz-scheduler-") for j in jars):
        out.add("FAIL", "SI66", "pom.xml: no plugin-quartz-scheduler: every daemon runs on every replica")
        n += 1
    elif not re.search(r"^\s*quartzscheduler\.cluster\.enable\s*=\s*true", override, re.M):
        out.add("FAIL", "SI66", "conf/override: no quartzscheduler.cluster.enable=true: the plugin ships false, the exclusive daemons run on every replica")
        n += 1
    exclusive = set(re.findall(r"^\s*quartzscheduler\.daemon\.([^.\s]+)\.disallowedClusterConcurrentExecution\s*=\s*true", override, re.M))
    if "plugin-quartz-scheduler" in deps and not exclusive:
        out.add("WARN", "SI66", "conf/override: no daemon declared exclusive (quartzscheduler.daemon.<id>.disallowedClusterConcurrentExecution=true)")
        n += 1
    if war and exclusive:
        known = war_daemons(war)
        for d in sorted(exclusive - known):
            out.add("WARN", "SI66", f"conf/override: daemon {d} declared exclusive and declared by no descriptor of the war: the line does nothing")
            n += 1
        rest = sorted(known - exclusive - {"indexer", "threadLauncherDaemon"})
        if rest:
            out.add("INFO", "SI66", "daemons of the war running on every replica: " + ", ".join(rest))
    if any(j.startswith("ehcache-") for j in jars) and hazelcast:
        out.add("WARN", "SI67", "the war ships Ehcache: neutralise it (scope provided in the cluster profile)")
        n += 1
    if cluster and "${cluster.config}" not in server:
        out.add("WARN", "SI67", "server.xml: cluster.xml is not included through the cluster.config variable: the local profile cannot skip it")
        n += 1
    if cluster and "sessionCache-1.0" in server:
        out.add("WARN", "SI67", "server.xml: sessionCache-1.0 declared outside cluster.xml: the local profile still starts Hazelcast")
        n += 1
    if read_text(site.path / "Dockerfile") and "configure.sh" not in read_text(site.path / "Dockerfile"):
        out.add("WARN", "SI67", "Dockerfile: no configure.sh: the war is not expanded and the session library finds no jar")
        n += 1
    forms = "forms-starter" in deps or "plugin-forms" in deps or any(j.startswith("plugin-forms-") for j in jars)
    if forms and not re.search(r"^\s*forms\.index\.writer\.ms\.timeout\.lock\s*=", override, re.M):
        out.add("WARN", "SI68", "conf/override: no forms.index.writer.ms.timeout.lock: a lock left by a stopped replica blocks the Forms indexing 15 min")
        n += 1
    if not n:
        out.passed("SI60", "multi-instance configuration of the site")


def check_kubernetes(site, k8s, out):
    """SI70-SI72: the Kubernetes manifests (or chart templates) of a multi-instance site, read as text: pod lifecycle,
    probes, Liquibase and the shared Forms index; Hazelcast discovery; ingress replay and affinity cookie."""
    files = sorted(p for p in pathlib.Path(k8s).rglob("*") if p.suffix in (".yaml", ".yml", ".tpl"))
    text = "\n".join(read_text(f) for f in files)
    if not text:
        out.add("WARN", "SI70", f"{k8s}: no manifest read")
        return
    deps = [d["artifactId"] for d in site.dependencies()]
    n = 0
    grace = re.search(r"terminationGracePeriodSeconds:\s*(\d+)", text)
    for cond, why in ((not grace or int(grace.group(1)) < 55, "terminationGracePeriodSeconds below preStop + the 45 s graceful shutdown of Hazelcast"),
                      ("preStop" not in text, "no preStop: the pod still receives requests while it stops (502)"),
                      ("startupProbe" not in text, "no startupProbe"),
                      (re.search(r"livenessProbe:(?:(?!readinessProbe|startupProbe).)*?/health/ready", text, re.S) is not None,
                       "liveness on /health/ready: a database outage restarts every replica"),
                      ("liquibase.enabled.at.startup=false" not in text, "Liquibase not disabled on the replicas (-Dliquibase.enabled.at.startup=false)"),
                      (("forms-starter" in deps or "plugin-forms" in deps) and "forms.internalIndexer.lucene.indexPath" not in text,
                       "no forms.internalIndexer.lucene.indexPath: the Forms index stays local to each pod"),
                      (("forms-starter" in deps or "plugin-forms" in deps) and "ReadWriteMany" not in text, "no ReadWriteMany volume for the Forms index")):
        if cond:
            out.add("WARN", "SI70", why)
            n += 1
    if ("hazelcast" in text.lower() or "5701" in text) and not (re.search(r"kind:\s*Role\b", text) and "endpoints" in text):
        out.add("WARN", "SI71", "no Role granting get/list on endpoints, pods, services: the Kubernetes discovery of Hazelcast fails")
        n += 1
    if "5701" not in text:
        out.add("WARN", "SI71", "no Service on port 5701 for the Hazelcast discovery")
        n += 1
    if re.search(r"session-cookie-name:\s*\"?JSESSIONID", text):
        out.add("FAIL", "SI72", "ingress affinity cookie named JSESSIONID: it collides with the OpenLiberty cookie, the route is lost after the first request")
        n += 1
    if re.search(r"proxy-next-upstream:\s*\"?[^\n]*non_idempotent", text):
        out.add("FAIL", "SI72", "proxy-next-upstream replays non-idempotent requests: a POST already sent is replayed on another pod")
        n += 1
    if "kind: Ingress" in text and "proxy-next-upstream" not in text:
        out.add("WARN", "SI72", "ingress without proxy-next-upstream \"error timeout\": a request to a killed pod is not retried on another")
        n += 1
    if not n:
        out.passed("SI70", f"Kubernetes manifests of {k8s}")


def check_webapp(site, war, m2, out):
    """SI50-SI58: the files of the site overlay: templates, JSP, web.xml, and files the site or its dependencies both ship."""
    for f in site.files("WEB-INF/templates"):
        text = (site.webapp / f).read_text(encoding="utf-8", errors="replace")
        if re.search(r"\?new\s*\(|\?api\b", text):
            out.add("FAIL", "SI52", f"webapp/{f}: ?new / ?api are forbidden by the v8 FreeMarker configuration")
        for macro in REMOVED_MACROS:
            if re.search(rf"<@{macro}\b", text):
                out.add("FAIL", "SI53", f"webapp/{f}: macro {macro} no longer exists in the v8 core")
        if "bypassXssFilter" in text:
            out.add("FAIL", "SI53", f"webapp/{f}: parameter bypassXssFilter no longer exists on the v8 macros")
        if re.fullmatch(r"WEB-INF/templates/commons[^/]*\.html", f) or "/corporate/" in f:
            out.add("FAIL", "SI54", f"webapp/{f}: a copy of a core commons/corporate template freezes v7 macros; drop it or rebuild it from the v8 core")
    for f in site.files("jsp"):
        if (site.webapp / f).read_text(encoding="utf-8", errors="replace").count("jsp:useBean"):
            out.add("FAIL", "SI55", f"webapp/{f}: jsp:useBean bypasses CDI; a v8 JSP gets its bean from CDI (see rules/jsp-admin.md)")
    web = site.webapp / "WEB-INF/web.xml"
    if web.exists():
        t = re.sub(r"<!--.*?-->", "", web.read_text(encoding="utf-8", errors="replace"), flags=re.S)
        root_ns = (re.search(r"<web-app[^>]*\sxmlns=\"([^\"]+)\"", t) or [None, ""])[1]
        listeners = re.findall(r"<listener-class>\s*([^<\s]+)\s*</listener-class>", t)
        if root_ns in ("http://java.sun.com/xml/ns/javaee", "http://xmlns.jcp.org/xml/ns/javaee") or any(l.endswith(("AppInitListener", "RequestContextListener")) for l in listeners):
            out.add("FAIL", "SI56", "webapp/WEB-INF/web.xml: a v7 descriptor (javaee namespace, AppInitListener or Spring listener); a site ships no web.xml unless it must, and then the v8 core's one adapted")
    if war and m2:
        check_overlay(site, war, m2, out)


def dependency_zips(site, war, m2):
    """Maps every webapp path shipped by a dependency of the war (a jar of WEB-INF/lib, or a lutece-site dependency of
    the pom: a pack or a theme) to the artefacts whose webapp zip ships it."""
    m2 = pathlib.Path(m2)
    provided = {}
    packs = [(d["groupId"], d["artifactId"], d["version"].strip("[]()").split(",")[0], "")
             for d in site.dependencies() if d["type"] == "lutece-site" and d["version"]]
    for group, art, ver, _ in list(war.artefacts()) + packs:
        base = m2 / group.replace(".", "/") / art / ver
        for z in sorted(base.glob(f"{art}-*webapp.zip")):
            try:
                with zipfile.ZipFile(z) as zz:
                    for n in zz.namelist():
                        if not n.endswith("/") and all(a != f"{art}-{ver}" for a, _, _ in provided.get(n, [])):
                            provided.setdefault(n, []).append((f"{art}-{ver}", z, n))
            except zipfile.BadZipFile:
                continue
    return provided


def check_overlay(site, war, m2, out):
    """SI50, SI57, SI58: overridden files, and files two dependencies ship (the unzip order between them is random)."""
    provided = dependency_zips(site, war, m2)
    own = set(site.files())
    for f in sorted(own & set(provided)):
        if f.endswith((".properties", ".dat")):
            continue
        sources = provided[f]
        out.add("WARN", "SI50", f"webapp/{f} replaces the file of {', '.join(s[0] for s in sources)}: re-read it against that version at every update")
    for f, sources in sorted(provided.items()):
        arts = sorted({s[0] for s in sources})
        if len([a for a in arts if not a.startswith("lutece-core")]) > 1 and f not in own:
            out.add("WARN", "SI57", f"{f} is shipped by {', '.join(arts)}: which one lands in the war depends on an unordered set")
        if f == "WEB-INF/plugins/plugins.dat" and any(not a.startswith("lutece-core") for a in arts) and f not in own:
            out.add("FAIL", "SI58", f"WEB-INF/plugins/plugins.dat comes from {', '.join(arts)}, not from the site: ship the site's own plugins.dat")


def read_decisions(path):
    """kind -> {id: reason} from a decisions file; a reason shorter than 12 characters does not count."""
    res = {"key": {}, "plugin": {}, "file": {}, "profile": {}}
    if path and pathlib.Path(path).exists():
        for line in pathlib.Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
            m = DECISION.match(line)
            if m and len(m.group(3).strip()) >= 12:
                res[m.group(1)][m.group(2)] = m.group(3).strip()
    return res


def check_invariants(site, before, after, before_ref, decisions, out, as_profile=None):
    """SI80-SI86: what the site shipped before and ships after, every difference answered by a decision. With
    as_profile, the before war is one environment of a v7 site and the after war is read under that profile only."""
    d = read_decisions(decisions)
    todo = []
    profiles = sorted(set(before.profiles()) | set(after.profiles()))
    site_before = {f"webapp/{r}" for r in before_site_files(site, before_ref, as_profile)} if before_ref else None
    site_after = {f"webapp/{r}" for r in site.files()}
    files_before = {str(x.relative_to(before.path)) for x in (before.path / "WEB-INF/conf").rglob("*.properties")}
    files_after = {str(x.relative_to(after.path)) for x in (after.path / "WEB-INF/conf").rglob("*.properties")}
    art = lambda origin: re.sub(r"-\d[\w.\-]*\.jar!.*$", "", origin) if "!" in origin else None
    arts_before = {art(o) for _, o, _ in before.jar_sources()}
    arts_after = {art(o) for _, o, _ in after.jar_sources()}

    def owner(origin, side):
        """Who sets a value: the site, an artefact present on one side only, the same artefact on both sides."""
        if origin == "absent":
            return "absent"
        own = site_before if side == "before" else site_after
        if own is None:
            own_hit = "/override/" in origin
        else:
            own_hit = f"webapp/{origin}" in own
        if own_hit:
            return "site"
        if "!" in origin:
            return "both" if art(origin) in arts_before and art(origin) in arts_after else side
        return "both" if origin in files_before and origin in files_after else side

    changes, gone_with, upstream, logging = {}, {}, [], {}
    read_after = set(after.strings())
    for _, name, files in after.sources():
        if "!" not in name:
            for _, pairs in files:
                read_after.update(k for k, _ in pairs)
    for profile in ([as_profile] if as_profile is not None else [""] + profiles):
        eb, ea = before.effective("" if as_profile is not None else profile), after.effective(profile)
        for k in sorted(set(eb) | set(ea)):
            if k in d["key"]:
                continue
            if k not in eb:
                va = ea[k]
                if va[0] is not None and "!" in va[1] and owner(va[1], "after") == "after" and k in read_after:
                    changes.setdefault(k, {}).setdefault(((None, "absent"), va), []).append(profile or "no profile")
                elif va[0] is not None and owner(va[1], "after") != "site":
                    upstream.append(f"{k} ({profile or 'no profile'}): new, {shown_value(k, va[0])} [{va[1]}]")
                continue
            vb, va = eb[k], ea.get(k, (None, "absent"))
            if vb[0] == va[0]:
                continue
            ob, oa = owner(vb[1], "before"), owner(va[1], "after")
            if vb[1].endswith("/log.properties") and va[0] is None:
                logging.setdefault(vb[1], set()).add(k)
                continue
            if "site" in (ob, oa) or oa == "after":
                changes.setdefault(k, {}).setdefault((vb, va), []).append(profile or "no profile")
            elif oa == "absent" and ob == "before":
                gone_with.setdefault(vb[1], set()).add(k)
            else:
                upstream.append(f"{k} ({profile or 'no profile'}): {shown_value(k, vb[0])} -> {shown_value(k, va[0])} [{vb[1]} -> {va[1]}]")
    shown = lambda v: "absent" if v[1] == "absent" and v[0] is None else ("masked (empty value)" if v[0] is None else shown_value(k, v[0]))
    for k, groups in sorted(changes.items()):
        for (vb, va), where in groups.items():
            scope = f"environment {as_profile}" if as_profile is not None else ("every profile" if len(where) == len(profiles) + 1 else ", ".join(where))
            out.add("FAIL", "SI80", f"{k} ({scope}): {shown(vb)} -> {shown(va)} [{vb[1]} -> {va[1]}]")
        todo.append(f"- key {k}: ")
    for origin, keys in sorted(logging.items()):
        if origin not in d["file"]:
            out.add("FAIL", "SI80", f"{origin}: {len(keys)} logging key(s) of v7 (log4j); v8 reads log4j2 files or the container: carry the levels and appenders the site needs, then answer `- file {origin}: …`")
            todo.append(f"- file {origin}: ")
    for origin, keys in sorted(gone_with.items()):
        out.add("INFO", "SI80", f"{origin}: its {len(keys)} key(s) are gone with the artefact that shipped it (answered by the plugin decision)")
    if upstream:
        report = after.path.parent / "site-check-upstream-config.txt"
        report.write_text("\n".join(sorted(set(upstream))) + "\n", encoding="utf-8")
        out.add("INFO", "SI85", f"{len(set(upstream))} default value(s) of the core or of a plugin changed between the two versions (the site sets none of them): {report}")
    pb, pa = before.plugins(), after.plugins()
    for n in sorted(set(pb) - set(pa)):
        if n not in d["plugin"]:
            out.add("FAIL", "SI81", f"plugin {n} {pb[n]['version']} ({pb[n]['file']}) shipped before, not after")
            todo.append(f"- plugin {n}: ")
    for n in sorted(set(pb) & set(pa)):
        if version_key(pa[n]["version"]) < version_key(pb[n]["version"]) and n not in d["plugin"]:
            out.add("WARN", "SI83", f"plugin {n}: {pb[n]['version']} -> {pa[n]['version']}, a lower version")
    for rel, content in sorted(before_site_files(site, before_ref, as_profile).items()):
        if rel.endswith(".properties") or rel == "WEB-INF/plugins/plugins.dat" or rel in d["file"]:
            continue
        fa = after.path / rel
        if not fa.exists():
            spring = " (a Spring context, which v8 ignores: confirm its beans are carried by keys or CDI)" if rel.endswith("_context.xml") else ""
            out.add("FAIL", "SI82", f"webapp/{rel}: the site shipped it before, the war no longer has it{spring}")
            todo.append(f"- file {rel}: ")
        elif fa.read_bytes() != content:
            origin = "the site's new version" if (site.webapp / rel).exists() else "a dependency's file"
            out.add("FAIL", "SI82", f"webapp/{rel}: the site's own file before, {origin} after: check nothing it did is lost")
            todo.append(f"- file {rel}: ")
    before_profiles = site_profiles(pairs for _, _, files in before.sources() for fname, pairs in files if "override" in fname)
    after_profiles = site_profiles(pairs for _, _, files in after.sources() for fname, pairs in files if "override" in fname)
    for p in sorted(set(before_profiles) ^ set(after_profiles)) if as_profile is None else []:
        if p not in d["profile"]:
            state = "named before, no longer after" if p in before_profiles else "new"
            out.add("FAIL", "SI84", f"profile {p}: {state}; the environments set the profile they run (mp.config.profile): confirm which one before renaming")
            todo.append(f"- profile {p}: ")
    for branch, count in later_commits(site, before_ref):
        out.add("WARN", "SI86", f"{branch} has {count} commit(s) after {before_ref} touching pom.xml, webapp/ or src/: compare with the tip of that branch, or port them")
    if todo:
        path = decisions or ".migration/site-decisions.md"
        out.add("FAIL", "SI80", f"{len(todo)} difference(s) without a decision: answer each in {path}, one line per difference, for example `{todo[0]}<why it is right>`")
    else:
        out.passed("SI80", "every difference between the two assembled sites is answered by a decision")


def later_commits(site, ref):
    """(branch, count) for every remote branch containing ref whose later commits change the site."""
    import subprocess
    if not ref:
        return []
    git = lambda *a: subprocess.run(["git", "-C", str(site.path), *a], capture_output=True, encoding="utf-8", errors="replace").stdout
    head = git("rev-parse", "HEAD").strip()
    res = []
    for b in git("branch", "-r", "--contains", ref, "--format=%(refname:short)").split():
        if b.endswith("/HEAD") or git("merge-base", "--is-ancestor", b, head) == "" and subprocess.run(
                ["git", "-C", str(site.path), "merge-base", "--is-ancestor", b, head]).returncode == 0:
            continue
        if subprocess.run(["git", "-C", str(site.path), "merge-base", "--is-ancestor", head, b]).returncode == 0:
            continue
        n = len(git("rev-list", f"{ref}..{b}", "--", "pom.xml", "webapp", "src").split())
        if n:
            res.append((b, n))
    return res


def before_site_files(site, ref, env=None):
    """path in the war -> content, of the site overlay at a git ref of the site repository: webapp/, then
    src/conf/default/, then src/conf/<env>/ when the before war is that environment (the order site-assembly copies them)."""
    import subprocess
    if not ref:
        return {}
    out = {}
    for prefix in ["webapp/", "src/conf/default/"] + ([f"src/conf/{env}/"] if env else []):
        names = subprocess.run(["git", "-C", str(site.path), "ls-tree", "-r", "--name-only", ref, "--", prefix],
                               capture_output=True, encoding="utf-8", errors="replace").stdout.split("\n")
        for n in filter(None, names):
            out[n[len(prefix):]] = subprocess.run(["git", "-C", str(site.path), "show", f"{ref}:{n}"], capture_output=True).stdout
    return out


def envconf(site_dir):
    """Merges src/conf/<env>/ of a v7 site into one profile-keyed override; returns (lines, unconverted files)."""
    site = pathlib.Path(site_dir)
    envs = sorted(d.name for d in (site / "src/conf").iterdir() if d.is_dir() and d.name != "default") if (site / "src/conf").is_dir() else []
    base = {}
    for f in sorted((site / "webapp/WEB-INF/conf").rglob("*.properties")) if (site / "webapp/WEB-INF/conf").is_dir() else []:
        rel = str(f.relative_to(site / "webapp"))
        if OVERRIDE_FILE.fullmatch(rel) and f.name != "log.properties":
            for k, v in read_properties(f):
                if not k.startswith("%"):
                    base[k] = (v, f"webapp/{rel}")
    per_env, unconverted = {}, []
    for env in envs:
        root = site / "src/conf" / env
        values = dict(base)
        for f in sorted(root.rglob("*")):
            if not f.is_file():
                continue
            rel = str(f.relative_to(root))
            if OVERRIDE_FILE.fullmatch(rel) and f.name != "log.properties":
                for k, v in read_properties(f):
                    values[k] = (v, f"src/conf/{env}/{rel}")
            else:
                unconverted.append(f"src/conf/{env}/{rel}")
        per_env[env] = values
    lines = []
    emit = lambda key, value: (f"# SECRET not copied, set it in Vault or the environment: {key}"
                               if SECRET_KEY.search(key) and not PLACEHOLDER.match(value.strip()) else f"{key}={escape_value(value)}")
    keys = sorted(set(base) | {k for v in per_env.values() for k in v})
    for k in keys:
        vals = {env: per_env[env].get(k) for env in envs}
        present = {e: v for e, v in vals.items() if v is not None}
        if len({v[0] for v in present.values()}) == 1 and len(present) == len(envs):
            v = next(iter(present.values()))
            lines.append(f"# {', '.join(sorted({x[1] for x in present.values()}))}")
            lines.append(emit(k, v[0]))
        else:
            for env, v in sorted(present.items()):
                lines.append(f"# {v[1]}")
                lines.append(emit(f"%{env}.{k}", v[0]))
            for env in sorted(set(envs) - set(present)):
                lines.append(f"# absent from src/conf/{env}: the environment {env} keeps the plugin's default")
    return envs, lines, unconverted


SPRING_READ = re.compile(r"WEB-INF/conf/(?:override/)?(?:plugins/)?[^/]+_context\.xml")


def spring_beans(path):
    """(bean id, property, value) of a Spring context file; list and set values joined with commas."""
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return []
    local = lambda el: el.tag.rsplit("}", 1)[-1]
    out = []
    for bean in root.iter():
        if local(bean) != "bean" or not bean.get("id"):
            continue
        for prop in [c for c in bean if local(c) == "property"]:
            if prop.get("value") is not None:
                value = prop.get("value")
            else:
                values = [(v.text or "").strip() for v in prop.iter() if local(v) == "value"]
                value = ",".join(values) if values else None
            if value is not None:
                out.append((bean.get("id"), prop.get("name"), value))
    return out


def spring_draft(site_dir, war):
    """Lines of override keys converting the Spring contexts of a site, with the candidates when no key matches."""
    site = pathlib.Path(site_dir)
    readable = set(war.strings())
    for _, _, files in war.sources():
        for _, pairs in files:
            readable.update(k for k, _ in pairs if not k.startswith("%"))
    roots = [("", site / "webapp")] + ([(d.name, d) for d in sorted((site / "src/conf").iterdir()) if d.is_dir()] if (site / "src/conf").is_dir() else [])
    lines = []
    for env, root in roots:
        for f in sorted(root.rglob("*_context.xml")) if root.exists() else []:
            if not SPRING_READ.fullmatch(str(f.relative_to(root))):
                lines.append(f"# NOT CONVERTED {f.relative_to(site)}: v7 never read a context there, its beans never applied")
                continue
            lines.append(f"# {f.relative_to(site)}")
            for bean, prop, value in spring_beans(f):
                key = f"{bean}.{prop}"
                prefix = f"%{env}." if env and env != "default" else ""
                if key in readable:
                    lines.append(f"# SECRET not copied, set it in Vault or the environment: {prefix}{key}"
                                 if SECRET_KEY.search(prop) and not PLACEHOLDER.match(value.strip()) else f"{prefix}{key}={escape_value(value)}")
                    continue
                head = bean.split(".")[0]
                cands = sorted(k for k in readable if KEY_LIKE.fullmatch(k) and k.rsplit(".", 1)[-1] in (prop, prop + "s", prop.rstrip("s")))
                near = [k for k in cands if k.startswith(head + ".")] or cands
                lines.append(f"# NO KEY {key} in the war; {'candidates: ' + ', '.join(near[:6]) if near else 'no key of the war ends with .' + prop + ': read the plugin sources (a producer, an @Alternative)'}")
    return lines


def rebase(site_dir, before, before_m2, after, after_m2, write):
    """Replays the site's overrides on the new upstream files; returns the number of files left with conflicts."""
    import subprocess
    import tempfile
    site = Site(site_dir)
    old, new = dependency_zips(site, War(before), before_m2), dependency_zips(site, War(after), after_m2)
    conflicts = 0
    for f in site.files():
        if f.endswith((".properties", ".dat")) or f not in old:
            continue
        read = lambda prov: zipfile.ZipFile(prov[f][-1][1]).read(prov[f][-1][2])
        base = read(old)
        mine = (site.webapp / f).read_bytes()
        if f not in new:
            print(f"GONE       {f}: {old[f][-1][0]} shipped it, no dependency ships it now: the override replaces nothing")
            continue
        theirs = read(new)
        with tempfile.TemporaryDirectory() as d:
            paths = [pathlib.Path(d, n) for n in ("v8", "v7", "site")]
            for path, data in zip(paths, (theirs, base, mine)):
                path.write_bytes(data)
            r = subprocess.run(["git", "merge-file", "-p", *map(str, paths)], capture_output=True)
        changed = sum(1 for a, b in zip(base.splitlines(), mine.splitlines()) if a != b) + abs(len(base.splitlines()) - len(mine.splitlines()))
        target = site.webapp / f
        if r.returncode == 0:
            print(f"CLEAN      {f}: {changed} line(s) of the site replayed on {new[f][-1][0]} (was {old[f][-1][0]})")
            if write:
                target.write_bytes(r.stdout)
        else:
            conflicts += 1
            print(f"CONFLICT   {f}: {r.returncode} conflict(s) replaying the site's lines on {new[f][-1][0]}: resolve {f}.conflict by hand")
            if write:
                target.with_name(target.name + ".conflict").write_bytes(r.stdout)
    return conflicts


def plugins_dat(war):
    """The lines of the plugins.dat an assembled site needs, from its plugin descriptors."""
    lines = ["core_extensions.installed=1"]
    for name, d in sorted(war.plugins().items()):
        lines.append(f"{name}.installed=1")
        if d["pool"] == "1":
            lines.append(f"{name}.pool=portal")
    return lines


def config_against(war, dump, profile):
    """Compares the effective configuration of the model with a runtime dump; returns the number of disagreements."""
    runtime = dict(parse_properties(pathlib.Path(dump).read_text(encoding="utf-8")))
    model = war.effective(profile)
    bad = 0
    for k, v in sorted(runtime.items()):
        mv = model.get(k, (None, "absent"))
        if mv[1] == "absent" or (mv[0] or "") == v or "*" in v:
            continue
        bad += 1
        print(f"  WARN [SI87] {k}: the container resolves {shown_value(k, v)!r}, the model {shown_value(k, mv[0])!r} from {mv[1]}")
    for k, (v, origin) in sorted(model.items()):
        if v is not None and k not in runtime and not k.startswith("%"):
            bad += 1
            print(f"  WARN [SI87] {k}: the model resolves {shown_value(k, v)!r} from {origin}, the container has no such key")
    print(f"TOTAL: {bad} disagreement(s) between the model and the running site")
    return bad


def fetch(url):
    """GETs a url, or returns None."""
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            return r.read().decode("utf-8", "replace")
    except Exception:
        return None


def lutece8_pom(pom):
    """Tells whether a pom text is a Lutece 8 artefact: a Lutece 8 parent, or no parent and a Lutece 8 core."""
    parent = re.search(r"<parent>.*?<version>([^<]+)</version>.*?</parent>", pom, re.S)
    core = re.search(r"<artifactId>lutece-core</artifactId>\s*<version>[\[(]?([^<,\])]+)", pom)
    return bool((parent and parent.group(1).startswith("8.")) or (not parent and core and core.group(1).startswith("8.")))


def local_v8(group, art, m2):
    """The newest version of an artefact in a local repository whose pom is a Lutece 8 one, or None."""
    base = pathlib.Path(m2) / group.replace(".", "/") / art if m2 else None
    if not base or not base.is_dir():
        return None
    for d in sorted((d for d in base.iterdir() if d.is_dir()), key=lambda d: version_key(d.name), reverse=True):
        pom = d / f"{art}-{d.name}.pom"
        if pom.exists() and lutece8_pom(pom.read_text(encoding="utf-8", errors="replace")):
            return d.name
    return None


def published_v8(group, art, extra=()):
    """The newest published version of an artefact whose pom is a Lutece 8 one, or None."""
    for repo in list(REPOSITORIES) + list(extra):
        meta = fetch(f"{repo}/{group.replace('.', '/')}/{art}/maven-metadata.xml")
        if not meta:
            continue
        for v in sorted(re.findall(r"<version>([^<]+)</version>", meta), key=version_key, reverse=True)[:6]:
            name = v
            if v.endswith("-SNAPSHOT"):
                vm = fetch(f"{repo}/{group.replace('.', '/')}/{art}/{v}/maven-metadata.xml") or ""
                ts = re.search(r"<timestamp>([^<]+)</timestamp>\s*<buildNumber>(\d+)</buildNumber>", vm)
                if not ts:
                    continue
                name = v.replace("SNAPSHOT", f"{ts.group(1)}-{ts.group(2)}")
            pom = fetch(f"{repo}/{group.replace('.', '/')}/{art}/{v}/{art}-{name}.pom") or ""
            if lutece8_pom(pom):
                return v
    return None


def successors():
    """artifactId -> (successor, evidence): site-successors.tsv next to this tool (public artefacts), then the
    organisation's own file ($LUTECEPOWERS_SITE_SUCCESSORS, else ~/.config/lutecepowers/site-successors.tsv), which
    names its private themes and packs and stays out of the toolkit."""
    files = [pathlib.Path(__file__).with_name("site-successors.tsv"),
             pathlib.Path(os.environ.get("LUTECEPOWERS_SITE_SUCCESSORS", os.path.expanduser("~/.config/lutecepowers/site-successors.tsv")))]
    res = {}
    for f in files:
        rows = [l.split("\t") for l in f.read_text(encoding="utf-8").splitlines() if l and not l.startswith("#")] if f.is_file() else []
        res.update({r[0]: (r[1], r[2]) for r in rows if len(r) >= 3})
    return res


def direct_parents(tree_file):
    """artifactId -> the direct dependency of the site that brings it, from a mvn dependency:tree output."""
    res, top = {}, None
    for line in pathlib.Path(tree_file).read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^([| +\\-]*)([\w.\-]+):([\w.\-]+):", line)
        if not m or not m.group(1):
            continue
        depth = len(m.group(1)) // 3
        if depth == 1:
            top = m.group(3)
        elif top:
            res.setdefault(m.group(3), top)
    return res


def gate(war_dir, bom, offline, site_dir=None, m2=None, extra=()):
    """Prints the Lutece 8 status of every Lutece artefact of an assembled site, and of the lutece-site dependencies
    (theme, pack) of its pom, which leave no jar in the war; returns 1 when one has no Lutece 8 version."""
    war = War(war_dir)
    managed = bom_versions(bom) if bom else {}
    known = successors()
    tree = pathlib.Path(str(war_dir).rstrip("/") + ".tree")
    via = direct_parents(tree) if tree.is_file() else {}
    missing = snapshots = 0
    print(f"# site {war_dir}: lutece-core {war.core_version}; target BOM {bom or 'none'}")
    if not war.v8():
        for jar in war.jars():
            try:
                with zipfile.ZipFile(jar) as z:
                    if not any(n.startswith("META-INF/maven/fr.paris.lutece") for n in z.namelist()):
                        continue
                    names = [n for n in z.namelist() if n.endswith(".class") and not n.endswith("module-info.class") and not n.startswith("META-INF/")]
                    heads = [z.read(n)[:8] for n in names[:20]]
                    major = max((struct.unpack(">H", h[6:8])[0] for h in heads if len(h) == 8 and h[:4] == b"\xca\xfe\xba\xbe"), default=0)
            except (zipfile.BadZipFile, OSError, struct.error):
                continue
            if major > 55:
                print(f"DRIFT      {jar.name:48} built for Java {major - 44}: this v7 war is not what the environments run, a range resolved past v7; rebuild it with site-assemble.sh --pin <group>:<artifact>:<the v7 version>")
    artefacts = list(war.artefacts())
    if site_dir:
        artefacts += [(d["groupId"], d["artifactId"], d["version"], "") for d in Site(site_dir).dependencies()
                      if d["type"] == "lutece-site"]
    seen = set()
    for group, art, ver, jar in sorted(artefacts, key=lambda a: (a[1], a[3] == "")):
        if not group.startswith("fr.paris.lutece") or art in seen:
            continue
        seen.add(art)
        if art in managed and managed[art][0].endswith("-SNAPSHOT"):
            snapshots += 1
            print(f"SNAPSHOT   {art:48} {ver:24} -> {managed[art][0]} (managed by lutece-bom as a snapshot: a site released on it moves under its feet; pin its last release)")
            continue
        if art in managed:
            print(f"BOM        {art:48} {ver:24} -> {managed[art][0]}")
            continue
        bom_version = re.search(r"<artifactId>lutece-bom</artifactId>\s*<version>([^<]+)</version>", pathlib.Path(bom).read_text(encoding="utf-8", errors="replace")) if bom else None
        if art.endswith("-starter") and bom_version:
            print(f"STARTER    {art:48} {ver:24} -> {bom_version.group(1)} (the version of the target lutece-bom)")
            continue
        local = local_v8(group, art, m2)
        v8 = local or (None if offline else published_v8(group, art, extra))
        if local:
            print(f"LOCAL      {art:48} {ver:24} -> {local} (built in the local repository, not published where the build looks: pin it and publish it)")
        elif v8 and not v8.endswith("-SNAPSHOT"):
            print(f"PUBLISHED  {art:48} {ver:24} -> {v8} (not in the BOM: pin it)")
        elif v8:
            snapshots += 1
            print(f"SNAPSHOT   {art:48} {ver:24} -> {v8} (no Lutece 8 release yet: a site released on it moves under its feet)")
        else:
            missing += 1
            hint = f"successor {known[art][0]} ({known[art][1]})" if art in known else (
                "not checked (offline)" if offline else "no published version with a Lutece 8 parent: update it first (lutece-update-plugin)")
            origin = f" [brought by {via[art]}: if its Lutece 8 version no longer needs it, a plugin decision]" if art in via else ""
            print(f"NO-V8      {art:48} {ver:24} -> {hint}{origin}")
    print(f"TOTAL: {missing} artefact(s) without a Lutece 8 version, {snapshots} with a Lutece 8 snapshot only")
    return 1 if missing else 0


def main():
    """Parses the command line and runs one command."""
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("site")
    c.add_argument("--war")
    c.add_argument("--before")
    c.add_argument("--before-ref")
    c.add_argument("--decisions")
    c.add_argument("--m2", default=os.path.expanduser("~/.m2/repository"))
    c.add_argument("--bom")
    c.add_argument("--k8s", help="the Kubernetes manifests or chart templates of the site (multi-instance checks SI70-SI72)")
    g = sub.add_parser("gate")
    g.add_argument("war")
    g.add_argument("--bom")
    g.add_argument("--offline", action="store_true")
    g.add_argument("--site", help="the site sources: their lutece-site dependencies (theme, pack) are checked too")
    g.add_argument("--m2", help="a local repository where private artefacts were built (read before the remote ones)")
    g.add_argument("--repo-url", action="append", default=[], help="another Maven repository to read (a private one)")
    f = sub.add_parser("config")
    f.add_argument("war")
    f.add_argument("--profile", default="")
    f.add_argument("--against")
    f.add_argument("--env", help="a file of NAME=VALUE lines: the environment of the container")
    rb = sub.add_parser("rebase")
    rb.add_argument("site")
    rb.add_argument("--before", required=True)
    rb.add_argument("--before-m2", required=True)
    rb.add_argument("--war", required=True)
    rb.add_argument("--m2", required=True)
    rb.add_argument("--write", action="store_true")
    sp = sub.add_parser("spring")
    sp.add_argument("site")
    sp.add_argument("--war", required=True)
    pd = sub.add_parser("plugins-dat")
    pd.add_argument("war")
    e = sub.add_parser("envconf")
    e.add_argument("site")
    e.add_argument("--out")
    t = sub.add_parser("takeover")
    t.add_argument("before")
    t.add_argument("after")
    t.add_argument("--out", required=True)
    c.add_argument("--as-profile")
    a = ap.parse_args()
    if a.cmd == "takeover":
        before, after = War(a.before), War(a.after)
        out = Findings()
        check_takeover(before, after, out)
        check_renames(before, after, out)
        os.makedirs(a.out, exist_ok=True)
        for name, text in zip(("takeover-1-core.sql", "takeover-2-components.sql"), takeover_plan(before, after)):
            pathlib.Path(a.out, name).write_text(text, encoding="utf-8")
            out.lines.append(f"  INFO [SI13] {os.path.join(a.out, name)}: {text.count(chr(10))} lines")
        out.print()
        return 1 if out.fail else 0
    if a.cmd == "gate":
        return gate(a.war, a.bom, a.offline, a.site, a.m2, a.repo_url)
    if a.cmd == "rebase":
        return 1 if rebase(a.site, a.before, a.before_m2, a.war, a.m2, a.write) else 0
    if a.cmd == "spring":
        print("\n".join(spring_draft(a.site, War(a.war))))
        return 0
    if a.cmd == "plugins-dat":
        print("\n".join(plugins_dat(War(a.war))))
        return 0
    if a.cmd == "envconf":
        envs, lines, unconverted = envconf(a.site)
        text = "\n".join([f"# Draft of WEB-INF/conf/override/profiles-config.properties from src/conf/{{{','.join(envs)}}}/",
                          "# Every profile name is an environment directory: confirm the profile each environment runs."] + lines) + "\n"
        if a.out:
            pathlib.Path(a.out).write_text(text, encoding="latin-1", errors="replace")
        else:
            print(text, end="")
        for f in unconverted:
            print(f"UNCONVERTED {f}", file=sys.stderr)
        return 0
    if a.cmd == "config":
        env = dict(l.split("=", 1) for l in pathlib.Path(a.env).read_text(encoding="utf-8", errors="replace").splitlines() if "=" in l) if a.env else None
        if a.against:
            return 1 if config_against(War(a.war, env), a.against, a.profile) else 0
        for k, (v, origin) in sorted(War(a.war).effective(a.profile).items()):
            print(f"{k}={'<masked: empty value>' if v is None else shown_value(k, v)}\t[{origin}]")
        return 0
    site = Site(a.site)
    war = War(a.war) if a.war else None
    bom = a.bom or latest_local_bom(a.m2)
    out = Findings()
    check_pom(site, bom, out, a.m2)
    check_build(site, out)
    check_secrets(site, out)
    check_conf(site, war, out)
    if war:
        check_plugins(site, war, out)
    check_cluster(site, war, out)
    if a.k8s:
        check_kubernetes(site, a.k8s, out)
    check_webapp(site, war, a.m2, out)
    if a.before:
        if not war:
            out.add("FAIL", "SI80", "--before needs --war: the two assembled sites are compared")
        else:
            check_takeover(War(a.before), war, out)
            check_renames(War(a.before), war, out)
            check_invariants(site, War(a.before), war, a.before_ref, a.decisions or str(site.path / ".migration/site-decisions.md"), out, a.as_profile)
    out.print()
    return 1 if out.fail else 0


if __name__ == "__main__":
    sys.exit(main())
