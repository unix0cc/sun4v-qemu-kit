#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# no-asm-warnings.sh -- the GNU build of the hypervisor produces no assembler or compiler warning and
# no failed file.
#
# Why this is a test and not a habit: build/hv_reset/gnu/build.sh hides stderr, and GNU as and Sun as do
# not always mean the same thing by the same source. The one that mattered:
#
#     set -1, %g5        Sun as: sethi+or, 0x00000000ffffffff  (32-bit operation, zero-extended)
#                        GNU as: mov -1,     0xffffffffffffffff (sign-extended), and only a warning:
#                                "set: number not in 0..4294967295 range"
#
# ldc.s compares a zero-extended lduw with CONS_BREAK (-1) / CONS_HUP (-2), so under GNU the comparison
# could never succeed. Nothing failed, nothing was reported. Found by comparing the two builds function
# by function (2026-09-29), fixed by a rewrite in fixup.sed, and this test keeps
# it from coming back: any new warning is either a new dialect difference or a real bug, and either way
# it should be looked at, not hidden.
#
# Measured: on the tree before the fix it fails with exactly three warnings (ldc.s:2340, ldc.s:2349,
# main.s:1094); after the fix it passes.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${OUTDIR:?set OUTDIR}"
"$HERE/../lib/build.sh"

# build.sh sends the assembler's and the compiler's stderr to a file per source (*.err, *.cpp.err), and shows it in the log only when
# a step fails: a warning of a step that succeeds is in those files and nowhere else, so they are read too.
log=$OUTDIR/build.log
all=$OUTDIR/.warnings-scan
{ cat "$log"; for e in "$OUTDIR"/*.err; do [ -f "$e" ] && sed "s|^|${e##*/}: |" "$e"; done; } > "$all" 2>/dev/null || true
w=$(grep -ciE 'warning:' "$all" || true)
f=$(grep -cE '^(ASM|C) FAIL ' "$log" || true)
if [ "$w" -ne 0 ] || [ "$f" -ne 0 ]; then
    echo "FAIL: $w warning(s), $f failed file(s) in the GNU hypervisor build ($log and the *.err files next to it):" >&2
    grep -iE 'warning:|^(ASM|C) FAIL ' "$all" | sort | uniq -c >&2
    exit 1
fi
echo "ok: no assembler/compiler warning and no failed file ($(ls "$OUTDIR"/*.o | wc -l) objects)"
