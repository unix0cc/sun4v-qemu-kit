#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""
Generate offsets.h from a Solaris-style offsets.in without Sun's `stabs` tool.

Sun's build does:

    grep '^#' offsets.in                     > offsets-n1.c
    cc -xdebugformat=stabs -g -S -o offsets-n1.s offsets-n1.c
    grep -v '^#' offsets.in                  > offsets.tmp
    stabs -t genassym -m lp64 offsets.tmp < offsets-n1.s > offsets.h

i.e. it compiles a stub to *stabs* debug format and mines struct layout out of
it.  Modern gcc cannot do that -- -gstabs was removed in GCC 13 -- so instead of
reading debug info we make the compiler compute the values for us, the classic
genassym trick used by Linux and the BSDs: emit an inline-asm marker whose
operand is a compile-time constant, then read the markers back out of the
generated assembly.

That has a useful property for this particular job: the numbers come from the
same compiler that will build the rest of the tree, so they cannot disagree with
it.  A stabs/DWARF reader can.

offsets.in syntax handled here:
    \\ ...            comment
    # ...            C preprocessor line -> copied into the stub verbatim
    name MACRO       struct at column 0   -> sizeof(struct name)
        memb MACRO   indented member      -> offsetof(struct name, memb)
        memb M1 M2   array member         -> M1 = offset, M2 = element stride
    \\#define ...   literal passthrough   -> copied into offsets.h verbatim
    \\ ...          comment
"""

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

MARK = "@@genassym@@"


def parse(src: str):
    """Return (preamble_lines, [(macro, kind, struct, member), ...])."""
    preamble, items, cur = [], [], None
    for raw in src.splitlines():
        if not raw.strip():
            continue
        if raw.lstrip().startswith("\\"):
            # `\#define FOO 1` is a literal line for the output file, not a
            # comment.  Sun's stabs copies it through untouched; several
            # macros in offsets.h (BANK_SHIFT, CB_LAST, the CPU_EVBSC_*(n)
            # accessors) exist only this way.
            body = raw.lstrip()[1:]
            if body.lstrip().startswith("#"):
                items.append((None, "literal", body.rstrip(), None))
            continue
        if raw.startswith("#"):
            preamble.append(raw)
            continue
        fields = raw.split()
        if len(fields) < 2:
            # A bare struct name with no size macro still opens a block.
            if fields and not raw[0].isspace():
                cur = fields[0]
            continue
        if raw[0].isspace():
            if cur is None:
                raise SyntaxError(f"member outside a struct: {raw!r}")
            items.append((fields[1], "off", cur, fields[0]))
            # Sun's stabs emits <MACRO>_INCR for *every* array member, whether
            # or not offsets.in names it explicitly.  Emit the same, under a
            # compile-time array test so pointer members yield 0 and get
            # dropped below.
            incr = fields[2] if len(fields) > 2 else fields[1] + "_INCR"
            items.append((incr, "incr", cur, fields[0]))
        else:
            cur = fields[0]
            items.append((fields[1], "size", cur, None))
            if len(fields) > 2:
                # A second macro on a *struct* line is log2(sizeof), the shift
                # used to index arrays of that struct.  Derived below from the
                # size rather than computed by the compiler.
                items.append((fields[2], "shift", cur, fields[1]))
    return preamble, items


def pre_h_lines(pre_includes, preamble):
    return [f"#include <{h}>" for h in pre_includes] + list(preamble)


SPELLING = {}

TAG_RE = re.compile(r"\b(struct|union)\s+(\w+)\s*\{")
TYPEDEF_RE = re.compile(r"\btypedef\b[^;{}]*?\b(\w+)\s*;")


def learn_spellings(preprocessed: str):
    """Decide, per type name, whether it is a struct, a union or a typedef.

    offsets.in just gives a bare name.  The tree uses all three: `config` is a
    struct, `err_diag_data` a union (error_defs.h), `ecc_mask_table_entry` a
    typedef of uint32_t.  Guessing wrong is not free -- writing `union X` for a
    struct tag is an error that also poisons the tag -- so read it off the
    preprocessed text instead.  struct/union tags win over typedefs, since a
    tagged type can also have a typedef of the same name.
    """
    for name in TYPEDEF_RE.findall(preprocessed):
        SPELLING.setdefault(name, name)
    for kw, name in TAG_RE.findall(preprocessed):
        SPELLING[name] = f"{kw} {name}"


ENUM_RE = re.compile(r"\benum\s+(?:\w+\s*)?\{([^{}]*)\}", re.S)


def enum_names(preprocessed: str):
    """Every enumerator visible in the stub, in declaration order.

    Sun's stabs emits these as ENUM_<enumerator> -- the Makefile's
    `egrep -v c-enum` filter is about malformed stabs lines, not about
    suppressing enums.  hcall_soft_state.s, for one, will not assemble
    without ENUM_HVctl_info_guest_soft_state.
    """
    seen, out = set(), []
    for body in ENUM_RE.findall(preprocessed):
        for part in body.split(","):
            part = part.split("=")[0].strip()
            if re.fullmatch(r"[A-Za-z_]\w*", part) and part not in seen:
                seen.add(part)
                out.append(part)
    return out


def emit_c(preamble, items, pre_includes=()) -> str:
    # offsets.in lists its includes in an order Sun's cc tolerated: several
    # headers declare `extern struct X arr[];` before X is complete, which
    # ISO C rejects and gcc enforces.  Hoisting the headers that *define*
    # those structs ahead of the list fixes it without touching offsets.in;
    # include guards make the repeat free.
    out = [f"#include <{h}>" for h in pre_includes]
    out += list(preamble)
    out += [
        "",
        f'#define GENASSYM(sym, val) '
        f'__asm__ __volatile__("\\n{MARK} " #sym " %0" : : "i" ((long)(val)))',
        "/* 1 for a real array, 0 for a pointer: an array's type differs from",
        "   the type of a pointer to its first element, a pointer's does not. */",
        "#define IS_ARRAY(x) "
        "(!__builtin_types_compatible_p(__typeof__(x), __typeof__(&(x)[0])))",
        "",
        "void __genassym(void);",
        "void __genassym(void) {",
    ]
    for macro, kind, struct, member in items:
        if kind == "literal":
            continue
        if kind == "shift":
            continue
        if kind == "enum":
            out.append(f"\tGENASSYM({macro}, ({struct}));")
        elif kind in ("size", "off", "incr"):
            # offsets.in names a type without saying what kind it is, and the
            # tree uses all three spellings: `config` is a struct,
            # `err_diag_data` a union, `ecc_mask_table_entry` a plain typedef
            # of uint32_t.  Which one is decided from the preprocessed text
            # (see spelling_of) rather than by trying all three -- probing
            # `union X` where X is a struct tag is itself an error, and it
            # poisons the tag for the probe that would have worked.
            spelling = SPELLING.get(struct, f"struct {struct}")
            if kind == "size":
                out.append(f"\tGENASSYM({macro}, sizeof ({spelling}));")
            elif kind == "off":
                out.append(f"\tGENASSYM({macro}, "
                           f"__builtin_offsetof({spelling}, {member}));")
            else:
                ref = f"((({spelling} *)0)->{member})"
                # __builtin_choose_expr does not type-check the branch it does
                # not take, so [0] need not be valid for scalar members.
                out.append(
                    f"\tGENASSYM({macro}, __builtin_choose_expr("
                    f"IS_ARRAY({ref}), sizeof {ref}[0], 0));")
        else:
            out.append(
                f"\tGENASSYM({macro}, __builtin_offsetof(struct {struct}, {member}));"
            )
    out += ["}", ""]
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("offsets_in")
    ap.add_argument("-o", "--output", default="-")
    ap.add_argument("--cc", default="sparc64-linux-gnu-gcc")
    ap.add_argument("--keep", metavar="DIR", help="keep the intermediate .c/.s here")
    ap.add_argument("--pre", default="", metavar="H,H,...",
                    help="headers to #include ahead of offsets.in's own list, to\nsatisfy 'extern struct X arr[]' declarations that appear before X is complete")
    ap.add_argument("cflags", nargs=argparse.REMAINDER,
                    help="everything after -- is passed to the compiler")
    args = ap.parse_args()

    cflags = [f for f in args.cflags if f != "--"]

    preamble, items = parse(Path(args.offsets_in).read_text(errors="replace"))
    pre = [h.strip() for h in args.pre.split(",") if h.strip()]

    # Enumerators are only discoverable after preprocessing, so do a cpp-only
    # pass over the preamble first and fold the results into the item list.
    with tempfile.TemporaryDirectory() as td:
        stub = Path(td) / "enums.c"
        stub.write_text("\n".join(pre_h_lines(pre, preamble)) + "\nint __e;\n")
        pp = subprocess.run([args.cc, "-E", *cflags, str(stub)],
                            capture_output=True, text=True)
    learn_spellings(pp.stdout)
    for name in enum_names(pp.stdout):
        items.append((f"ENUM_{name}", "enum", name, None))

    csrc = emit_c(preamble, items, pre)

    with tempfile.TemporaryDirectory() as td:
        work = Path(args.keep) if args.keep else Path(td)
        work.mkdir(parents=True, exist_ok=True)
        cfile, sfile = work / "genassym.c", work / "genassym.s"
        cfile.write_text(csrc)

        # -O1 is required: the operand must fold to a literal for the "i"
        # constraint.  -g is deliberately absent; we do not read debug info.
        cmd = [args.cc, "-S", "-O1", *cflags, "-o", str(sfile), str(cfile)]

        # A real offsets.in describes every struct the tree has, including ones
        # behind #ifdefs this particular variant does not enable.  Rather than
        # demand a perfect -D set up front, drop whatever will not compile and
        # say so: a named, counted list of skipped symbols is more useful than
        # an all-or-nothing failure, and the ones that do compile are still
        # exactly what the compiler thinks.
        skipped = []
        lines = csrc.splitlines()
        for _ in range(40):
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode == 0:
                break
            bad = set()
            for m in re.finditer(r"genassym\.c:(\d+):\d+: error:", proc.stderr):
                bad.add(int(m.group(1)) - 1)          # 0-based
            bad = {i for i in bad if 0 <= i < len(lines)
                   and lines[i].lstrip().startswith("GENASSYM(")}
            if not bad:
                sys.stderr.write(proc.stderr)
                sys.stderr.write("\n[genoffsets] compile failed for a reason "
                                 "that is not a per-symbol error\n")
                return 1
            for i in sorted(bad):
                m = re.search(r"GENASSYM\((\w+),", lines[i])
                if m:
                    skipped.append(m.group(1))
                lines[i] = "\t/* skipped: " + lines[i].strip() + " */"
            cfile.write_text("\n".join(lines) + "\n")
        else:
            sys.stderr.write("[genoffsets] gave up after 40 retry rounds\n")
            return 1

        if skipped:
            sys.stderr.write(
                f"[genoffsets] skipped {len(skipped)} symbol(s) that do not "
                f"compile under these flags:\n  " + " ".join(sorted(skipped)) + "\n")

        pat = re.compile(rf"{re.escape(MARK)}\s+(\S+)\s+(-?\d+)")
        found = {}
        for line in sfile.read_text(errors="replace").splitlines():
            m = pat.search(line)
            if m:
                found[m.group(1)] = int(m.group(2))

    missing = [macro for macro, kind, *_ in items
               if kind not in ("literal", "shift") and macro not in found]
    if missing:
        sys.stderr.write(
            f"[genoffsets] {len(missing)} symbol(s) produced no marker, "
            f"first few: {missing[:5]}\n"
        )

    lines = ["/* Generated by genoffsets.py -- do not edit. */", ""]
    for macro, kind, text_or_struct, _member in items:
        if kind == "shift":
            sz = found.get(_member)
            if sz and sz > 0 and (sz & (sz - 1)) == 0:
                lines.append(f"#define\t{macro.upper()} 0x{sz.bit_length() - 1:x}")
            continue
        if kind == "literal":
            lines.append(text_or_struct)
        elif macro in found:
            if kind == "incr" and found[macro] == 0:
                continue          # not an array; Sun emits no _INCR for these
            # Sun's stabs upper-cases the genassym name: offsets.in says
            # `ntsbs_ctxn CPU_NTSBS_CTXn`, the assembly references
            # CPU_NTSBS_CTXN, and Sun's offsets.h defines it upper-case.
            # Enum names are left alone -- Sun keeps ENUM_HVctl_op_hello.
            name = macro if kind == "enum" else macro.upper()
            lines.append(f"#define\t{name} 0x{found[macro]:x}")
    lines.append("")
    text = "\n".join(lines)

    if args.output == "-":
        sys.stdout.write(text)
    else:
        Path(args.output).write_text(text)
    n_lit = sum(1 for _, k, *_ in items if k == "literal")
    sys.stderr.write(
        f"[genoffsets] emitted {len(found)} computed + {n_lit} literal "
        f"of {len(items) - n_lit} requested\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
