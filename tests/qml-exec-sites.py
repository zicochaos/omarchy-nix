"""List the exec-ish call sites of a vendored Omarchy shell/ QML tree.

checks.omarchy-ux (tests/ux.nix, binary coverage) compares this output
with tests/fixtures/qml-exec-sites.txt, so an upstream bump that adds,
drops or changes an exec site shows up as a reviewable diff instead of
a bare count change.

A site is a QML line matching `Process {`, `Quickshell.execDetached` or
`Util.execDetached`. Output: one sorted line per site,
"<path relative to shell/>: <normalized site>":
  - execDetached: the call from the match through its closing
    parenthesis (continuation lines joined, whitespace collapsed);
  - Process: "Process <id>: command: <expr>" with the block's own `id`
    and `command` properties, "-" for one it does not declare (the
    command is then assigned from JavaScript elsewhere in the file).

Regenerate the fixture after reviewing the new sites (bump checklist,
docs/UPSTREAM.md):
  python3 tests/qml-exec-sites.py \
    "$(nix build --no-link --print-out-paths .#omarchy)/share/omarchy/shell" \
    > tests/fixtures/qml-exec-sites.txt
"""

import os
import re
import sys

SITE = re.compile(r"Process \{|Quickshell\.execDetached|Util\.execDetached")
OPEN = "([{"
CLOSE = ")]}"


def scan(text, start):
    """Yield (index, char) of code outside strings and comments."""
    i = start
    n = len(text)
    while i < n:
        c = text[i]
        if c in "\"'`":
            i += 1
            while i < n and text[i] != c:
                i += 2 if text[i] == "\\" else 1
            i += 1
            continue
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
            continue
        yield i, c
        i += 1


def balanced_end(text, start):
    """Index just past the bracket group opening at or after start."""
    depth = 0
    for i, c in scan(text, start):
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
            if depth == 0:
                return i + 1
    return len(text)


def collapse(s):
    return " ".join(s.split())


def exec_site(text, pos):
    paren = text.find("(", pos)
    line_end = text.find("\n", pos)
    line_end = len(text) if line_end < 0 else line_end
    if paren < 0 or paren > line_end:
        return collapse(text[pos:line_end])
    return collapse(text[pos : balanced_end(text, paren)])


def process_site(text, pos):
    brace = text.index("{", pos)
    end = balanced_end(text, brace)
    # Split the block body into its direct statements (newline or ';'
    # at nesting depth 0), so nested objects stay inside one statement.
    statements = []
    current = brace + 1
    depth = 0
    for i, c in scan(text, brace + 1):
        if i >= end - 1:
            break
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
        elif depth == 0 and c in "\n;":
            statements.append(text[current:i])
            current = i + 1
    statements.append(text[current : end - 1])
    props = {}
    for statement in statements:
        m = re.match(r"\s*(id|command)\s*:\s*(.*)", statement, re.DOTALL)
        if m and m.group(1) not in props:
            props[m.group(1)] = collapse(m.group(2))
    return "Process %s: command: %s" % (props.get("id", "-"), props.get("command", "-"))


def sites(shell_dir):
    out = []
    for root, dirs, files in os.walk(shell_dir):
        dirs.sort()
        for name in sorted(files):
            if not name.endswith(".qml"):
                continue
            path = os.path.join(root, name)
            rel = os.path.relpath(path, shell_dir)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            offset = 0
            for line in text.splitlines(keepends=True):
                m = SITE.search(line)
                if m:
                    pos = offset + m.start()
                    if m.group(0) == "Process {":
                        site = process_site(text, pos)
                    else:
                        site = exec_site(text, pos)
                    out.append("%s: %s" % (rel, site))
                offset += len(line)
    return sorted(out)


if __name__ == "__main__":
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        sys.exit("usage: qml-exec-sites.py <omarchy share/omarchy/shell dir>")
    found = sites(sys.argv[1])
    if not found:
        sys.exit("no exec sites found under %s (tree moved?)" % sys.argv[1])
    sys.stdout.write("".join(line + "\n" for line in found))
