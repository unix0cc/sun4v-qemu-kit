#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""
Implement Sun's `.pushlocals` / `.poplocals` for GNU as, by renumbering.

These directives scope numeric local labels so that a macro's own `1:` cannot
capture a `1f` written by the caller.  GNU as has no equivalent, and simply
deleting them -- which is what this build did at first -- silently changes
control flow:

    brnz  %i3, 1f          <- means the 1: after the abort
    nop
    HVABORT(...)           <- expands to four _PRINT_NOTRAP, each with its own 1:
    1:

With the directives gone, `1f` binds to the first `1:` *inside* HVABORT, so the
branch is taken straight into the abort it was meant to skip.  Nothing warns:
the code assembles, links and runs, it just goes to the wrong place.  This cost
a full debugging cycle to find.

`__COUNTER__` would be the obvious way to generate unique labels at the cpp
level, but the tree needs -traditional-cpp for its K&R token pasting, and
traditional mode does not expand it.  So do the renumbering here instead:
every `.pushlocals` region gets its own numeric namespace, which is exactly
what the directive means.  gas accepts arbitrary non-negative integers as
local labels, so region N uses STRIDE*(N+1) + d.  A label d of STRIDE or more
would land in the next region's numbers and bind to the wrong place without a
word (the failure this script exists to prevent), so it is refused: the output
then is a `.error` directive, which stops the assembler with the reason (the
build runs this in a pipe without pipefail, so an exit status alone would be lost).

Reads stdin, writes stdout.
"""

import re
import sys

# `N:` defines a local label, `Nf`/`Nb` reference the next/previous one.
LABEL = re.compile(r"(?<![\w.$])(\d+)(:)")
REF = re.compile(r"(?<![\w.$])(\d+)([fb])(?![\w.$])")

# Local labels of a region are numbered 0..STRIDE-1 (the tree uses 0..9).
STRIDE = 1000

PUSH = re.compile(r"\.pushlocals\b")
POP = re.compile(r"\.poplocals\b")


def main() -> int:
    try:
        return run()
    except LabelRange as e:
        msg = "pushlocals: %s" % e
        sys.stderr.write("[%s]\n" % msg)
        sys.stdout.write('.error "%s"\n' % msg)
        return 1


class LabelRange(Exception):
    pass


def run() -> int:
    text = sys.stdin.read()
    out = []
    stack = []          # active region bases, innermost last
    region = 0
    pos = 0

    # Walk directive by directive so the rewrite applies to exactly the text
    # between a push and its matching pop.
    for m in re.finditer(r"\.pushlocals\b|\.poplocals\b", text):
        chunk = text[pos:m.start()]
        out.append(rewrite(chunk, stack[-1] if stack else None))
        if m.group(0) == ".pushlocals":
            region += 1
            stack.append(STRIDE * (region + 1))
        else:
            if stack:
                stack.pop()
            else:
                sys.stderr.write("[pushlocals] .poplocals without .pushlocals\n")
        pos = m.end()

    out.append(rewrite(text[pos:], stack[-1] if stack else None))
    if stack:
        sys.stderr.write(f"[pushlocals] {len(stack)} unclosed .pushlocals\n")
    sys.stdout.write("".join(out))
    return 0


# Quoted strings must be stepped over, not rewritten.  _PRINT embeds its text
# inline as `.asciz "..."`, and that text is full of things that look like
# local labels -- the watchdog dump alone contains "%g0-%g3: 0 0 0 0", where
# the `3:` would otherwise be renumbered, silently corrupting the message and
# shifting every byte after it.  Caught by re-running cmp-objects.sh against
# Sun's binary, which is the only reason it was noticed at all.
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')


def rewrite(chunk: str, base):
    if base is None:
        return chunk
    out, pos = [], 0
    for s in STRING.finditer(chunk):
        out.append(renumber(chunk[pos:s.start()], base))
        out.append(s.group(0))          # verbatim
        pos = s.end()
    out.append(renumber(chunk[pos:], base))
    return "".join(out)


def renumber(text: str, base: int) -> str:
    def new(m):
        d = int(m.group(1))
        if d >= STRIDE:
            raise LabelRange("local label %d in a .pushlocals region is not below %d" % (d, STRIDE))
        return f"{base + d}{m.group(2)}"
    text = LABEL.sub(new, text)
    return REF.sub(new, text)


if __name__ == "__main__":
    sys.exit(main())
