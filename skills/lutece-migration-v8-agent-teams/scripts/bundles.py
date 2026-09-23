"""Reads Java .properties bundles the way java.util.Properties does: one entry per logical line (a line ending with
an odd number of backslashes continues on the next one), `#` and `!` comments, and a key ending at the first
unescaped `=`, `:` or whitespace. Every check that reads a bundle goes through here, so a continuation line such as
`   (0: no constraint)` is never taken for a key."""
import re

KEY = re.compile(r"((?:\\.|[^=:\s\\])+)[ \t\f]*[=:]?[ \t\f]*(.*)$", re.S)


def _continues(line):
    """True when the line ends with an odd number of backslashes."""
    return (len(line) - len(line.rstrip("\\"))) % 2 == 1


def spans(path):
    """(first physical line, last physical line, logical line) of each entry, continuations joined, comments skipped."""
    buf, start = None, 0
    n = 0
    for n, raw in enumerate(open(path, encoding="latin-1", newline=""), 1):
        line = raw.rstrip("\r\n")
        if buf is None:
            stripped = line.lstrip(" \t\f")
            if not stripped or stripped[0] in "#!":
                continue
            buf, start = stripped, n
        else:
            buf += line.lstrip(" \t\f")
        if _continues(buf):
            buf = buf[:-1]
            continue
        yield start, n, buf
        buf = None
    if buf is not None:
        yield start, n, buf


def logical_lines(path):
    """(number of the first physical line, logical line) of each entry."""
    for start, _, line in spans(path):
        yield start, line


def entries(path):
    """(line number, key, raw value) of each entry of a bundle."""
    for n, line in logical_lines(path):
        m = KEY.match(line)
        if m:
            yield n, m.group(1), m.group(2)


def keys(path):
    """The set of keys a bundle declares."""
    return {k for _, k, _ in entries(path)}
