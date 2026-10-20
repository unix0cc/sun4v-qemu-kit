#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""
Build an override include tree that neutralises Sun's forward-use declarations.

Several OpenSPARC hv headers declare

    extern struct mau       maus[];
    extern strand_t         strands[];
    extern struct guest_console_queues cons_queues[];

at a point where the element type is still incomplete, because the headers
include each other in a cycle (mau.h -> platform/mau.h -> config.h ->
platform/config.h, and the last one already wants struct mau).  Sun's cc
accepted it; ISO C does not, and gcc enforces the rule.

Rather than patch the reference tree -- which is verified byte-perfect against
the OpenSPARC tarball and must stay that way -- this builds a shadow directory
holding copies of just the offending headers with just those declarations
commented out, to be placed first on the include path.  Nothing else in the
tree is touched, and the shadow is regenerated from scratch each run.

Driven by the compiler: compile, read "array type has incomplete element type"
diagnostics, patch that exact line, repeat until the error class is gone.
The declarations being removed are of arrays nothing in the offsets stub
references, so removing them cannot change any offset.
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ERR = re.compile(
    r"^(?P<file>/[^:]+):(?P<line>\d+):\d+: error: array type has "
    r"incomplete element type", re.M)


def rel_to_include(path: Path, incdirs) -> Path:
    """Map an absolute header path to its path relative to whichever -I covers it."""
    best = None
    for d in incdirs:
        try:
            r = path.relative_to(d)
        except ValueError:
            continue
        if best is None or len(r.parts) < len(best.parts):
            best = r
    return best or Path(path.name)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--override", required=True, help="shadow include dir to build")
    ap.add_argument("--cc", default="sparc64-linux-gnu-gcc")
    ap.add_argument("--probe", required=True, help="C file to compile as the probe")
    ap.add_argument("--max-rounds", type=int, default=60)
    ap.add_argument("cflags", nargs=argparse.REMAINDER)
    args = ap.parse_args()

    cflags = [f for f in args.cflags if f != "--"]
    incdirs = [Path(f[2:]).resolve() for f in cflags if f.startswith("-I")]

    out = Path(args.override)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    patched, relocated = {}, {}
    for _ in range(args.max_rounds):
        proc = subprocess.run(
            [args.cc, "-fsyntax-only", *cflags, args.probe],
            capture_output=True, text=True)
        hits = [(Path(m.group("file")), int(m.group("line")))
                for m in ERR.finditer(proc.stderr)]
        if not hits:
            if proc.returncode != 0:
                sys.stderr.write(
                    "[mkoverrides] no more incomplete-element errors; other "
                    "diagnostics remain (that may be fine)\n")
            break
        for src, lineno in hits:
            rel = rel_to_include(src.resolve(), incdirs)
            dst = out / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if not dst.exists():
                shutil.copy2(src, dst)
            lines = dst.read_text(errors="replace").splitlines(keepends=True)
            i = lineno - 1
            if not (0 <= i < len(lines)) or lines[i].lstrip().startswith("/*"):
                continue
            decl = lines[i].strip()
            if decl in relocated.get(str(rel), ()):
                # This is the copy we already moved to the end of the file, and
                # the type is still incomplete even there.  Nothing more to try:
                # drop it.  Safe for the offsets stub, which never references
                # these arrays; a C file that needs one will say so at compile
                # time and can be given the declaration explicitly.
                lines[i] = ("/* mkoverrides: element type incomplete even at "
                            "end of file, dropped: " + decl + " */\n")
                dst.write_text("".join(lines))
                continue
            lines[i] = ("/* mkoverrides: element type incomplete here, "
                        "moved to end of file: " + decl + " */\n")
            # Move rather than delete where possible: the offsets stub never
            # references these arrays, but the C files do, and by the end of
            # the header the type is usually complete (the platform header
            # that defines it has been included by then).  The guard matters
            # -- without it the C declaration leaks into every .s file that
            # includes this header and the assembler chokes on `extern`.
            lines.append("\n#ifndef _ASM\n" + decl + "\n#endif\n")
            dst.write_text("".join(lines))
            relocated.setdefault(str(rel), set()).add(decl)
            patched.setdefault(str(rel), []).append(lineno)
    else:
        sys.stderr.write("[mkoverrides] gave up; too many rounds\n")
        return 1

    # A declaration that is still incomplete at the end of its own header gets
    # dropped above.  Put it at the end of the header that *defines* the type
    # instead -- there it is always complete -- so the C files that use the
    # array still see a declaration.  Guarded, so it never reaches assembly.
    dropped = re.compile(r"dropped: (extern [^*]*?\[\];)")
    decl_head = re.compile(r"extern\s+(?:(struct|union)\s+)?(\w+)")
    for f in sorted(out.rglob("*.h")):
        for decl in dropped.findall(f.read_text(errors="replace")):
            m = decl_head.search(decl)
            if not m:
                continue
            kw, name = m.group(1), m.group(2)
            pat = (re.compile(rf"^{kw}\s+{name}\s*\{{", re.M) if kw else
                   re.compile(rf"^\s*\}}\s*{name}\s*;|^typedef[^;]*\b{name}\s*;", re.M))
            for d in incdirs:
                for h in d.rglob("*.h"):
                    try:
                        if not pat.search(h.read_text(errors="replace")):
                            continue
                    except OSError:
                        continue
                    dst = out / h.name
                    if not dst.exists():
                        shutil.copy2(h, dst)
                    if decl not in dst.read_text(errors="replace"):
                        with dst.open("a") as fh:
                            fh.write("\n#ifndef _ASM\n" + decl + "\n#endif\n")
                        print(f"{h.name}: relocated to defining header: {decl}")
                    break
                else:
                    continue
                break

    for rel, lns in sorted(patched.items()):
        print(f"{rel}: neutralised line(s) {', '.join(map(str, lns))}")
    print(f"[mkoverrides] {sum(len(v) for v in patched.values())} declaration(s) "
          f"in {len(patched)} header(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
