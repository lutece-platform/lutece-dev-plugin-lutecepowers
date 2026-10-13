#!/usr/bin/env python3
"""maven-net.py — the network side of a Maven run the bench starts with its own settings file.

Usage:
  maven-net.py merge <bench_settings> <user_settings> <out>   the bench settings with the user's proxies and mirrors
  maven-net.py probe <settings> <url> ...                     fails when a repository does not answer in 10 s

merge: the user's proxies replace the bench's, the user's mirrors whose id the bench file lacks are added; nothing
else of the user's file (servers, profiles, local repository) is copied. The output is written readable by its owner
only.
probe: each URL, and each mirror of the settings, is requested the way Maven routes it: through the active proxy of
its scheme unless its host matches nonProxyHosts. A mirror of every repository (mirrorOf *) replaces the URLs given.
Any HTTP answer counts as reachable; a URL without one in 10 s is printed with its route, exit 1.
"""
import concurrent.futures
import fnmatch
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

TIMEOUT = 10


def load(path):
    """Parses a settings file with its namespace stripped; an absent or empty file gives an empty settings element."""
    if not path or not os.path.isfile(path) or not os.path.getsize(path):
        return ET.Element("settings")
    root = ET.parse(path).getroot()
    for e in root.iter():
        if isinstance(e.tag, str) and "}" in e.tag:
            e.tag = e.tag.split("}", 1)[1]
    return root


def text(e, tag, default=""):
    """Returns the stripped text of a child element, else the default."""
    c = e.find(tag)
    return (c.text or "").strip() if c is not None and c.text else default


def merge(bench, user, out):
    """Writes the bench settings with the user's proxies and the user's mirrors the bench file does not declare."""
    b, u = load(bench), load(user)
    uproxies = u.find("proxies")
    if uproxies is not None and len(uproxies):
        old = b.find("proxies")
        if old is not None:
            b.remove(old)
        b.insert(0, uproxies)
    umirrors = u.find("mirrors")
    if umirrors is not None and len(umirrors):
        bmirrors = b.find("mirrors")
        if bmirrors is None:
            bmirrors = ET.SubElement(b, "mirrors")
        ids = {text(m, "id") for m in bmirrors.findall("mirror")}
        for m in umirrors.findall("mirror"):
            if text(m, "id") not in ids:
                bmirrors.append(m)
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "wb") as f:
        ET.ElementTree(b).write(f, encoding="utf-8", xml_declaration=True)


def route(settings, url):
    """Returns the proxy URL Maven would use for url, or None for a direct connection."""
    host = (urllib.parse.urlsplit(url).hostname or "").lower()
    scheme = urllib.parse.urlsplit(url).scheme
    active = [p for p in settings.findall("proxies/proxy") if text(p, "active", "true").lower() != "false"]
    chosen = next((p for p in active if text(p, "protocol", "http").lower() == scheme), active[0] if active else None)
    if chosen is None:
        return None
    for pattern in text(chosen, "nonProxyHosts").replace(",", "|").split("|"):
        pattern = pattern.strip().lower()
        if pattern and (fnmatch.fnmatch(host, pattern) or pattern.startswith(".") and host.endswith(pattern)):
            return None
    auth = ""
    if text(chosen, "username"):
        auth = "%s:%s@" % (urllib.parse.quote(text(chosen, "username"), safe=""),
                           urllib.parse.quote(text(chosen, "password"), safe=""))
    return "http://%s%s:%s" % (auth, text(chosen, "host"), text(chosen, "port", "80"))


def answers(url, proxy):
    """Returns None when url gives any HTTP answer within the timeout, else the error."""
    handlers = [urllib.request.ProxyHandler({"http": proxy, "https": proxy} if proxy else {}),
                urllib.request.HTTPSHandler(context=ssl._create_unverified_context())]
    try:
        urllib.request.build_opener(*handlers).open(urllib.request.Request(url, method="HEAD"), timeout=TIMEOUT).close()
    except urllib.error.HTTPError:
        return None
    except Exception as e:
        return str(getattr(e, "reason", e)) or type(e).__name__
    return None


def probe(path, urls):
    """Requests every repository URL in parallel and prints those without an answer; returns the exit code."""
    settings = load(path)
    mirrors = settings.findall("mirrors/mirror")
    everything = [text(m, "url") for m in mirrors if text(m, "mirrorOf") == "*"]
    targets = everything or list(urls) + [text(m, "url") for m in mirrors]
    targets = list(dict.fromkeys(t for t in targets if t.startswith(("http://", "https://"))))
    routes = {t: route(settings, t) for t in targets}
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, len(targets))) as pool:
        errors = dict(zip(targets, pool.map(lambda t: answers(t, routes[t]), targets)))
    down = [t for t in targets if errors[t]]
    for t in down:
        via = "through the proxy %s" % urllib.parse.urlsplit(routes[t]).netloc.split("@")[-1] if routes[t] else "directly"
        print("  %s does not answer %s in %d s (%s)" % (t, via, TIMEOUT, errors[t]))
    return 1 if down else 0


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "merge":
        merge(*sys.argv[2:5])
    elif len(sys.argv) >= 4 and sys.argv[1] == "probe":
        sys.exit(probe(sys.argv[2], sys.argv[3:]))
    else:
        sys.exit(__doc__)
