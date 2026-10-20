#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# offsets-cross-check.sh -- offsets.h is computed two independent ways and the two agree; and for
# ontario/legion the file the build uses is the very file Sun's toolchain makes.
#
# The build (gnu/build-offsets.sh) takes the layout of the hypervisor's structs from DWARF:
# dwarf2genassym.pl reads what gcc recorded and applies the rules of Sun's `stabs`. That is one
# reading of one compiler's debug info. lib/genoffsets.py asks the same compiler a different way: it
# compiles inline-asm markers whose operands are offsetof()/sizeof() constants, so gcc itself
# evaluates them and no debug info is read. If the DWARF reader were ever wrong -- a new gcc spelling
# bit fields differently, a rule of offsets.in misread -- the two would disagree here.
#
# What it checks, on the build's own flags (build writes them to $OUTDIR/offsets.flags):
#   1. every numeric symbol both methods produce has the same value (0 mismatches), and there are
#      enough of them for that to mean something (the markers cannot reach everything: they only
#      emit what offsets.in names explicitly, so struct members it leaves unlisted -- the HDNAME_*
#      -- are the DWARF reader's alone; counted, not compared);
#   2. ontario/legion only: offsets.h and offsets.chk are byte-identical to gnu/reference/, which
#      Sun Studio 11 and `stabs` made from this offsets.in.
#
# Measured 2026-10-01 (ontario/legion): 932 numeric symbols agree, 0 mismatches; 96 more (the HDNAME_*, G,
# INS, OUTS and their _INCR) only the DWARF reader makes; the files equal the references.
#
# Shown failing -- three defects put into dwarf2genassym.pl in a copy of the tree, the build's own
# comparison with the reference (build-offsets.sh step 3) switched off with REFERENCE=/nonexistent:
#   member offset read as 0 (ignores DW_AT_data_member_location)
#                       FAIL at 1: 669 symbols differ, CB_ARG0 0x0 vs 0x10 ...
#   "no member list -> all members" rule removed
#                       passes 1 (the markers never reach those symbols), FAIL at 2: HDNAME_* missing
#   array stride halved (_INCR)
#                       never reaches the test: the build itself stops at the link (undefined hv_debug_flags)
# With the reference check left on, the build refuses all three before this test runs, as it should for
# ontario/legion; this test is for what that check cannot do: a variant with no reference, and the
# reference itself being wrong.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
: "${OUTDIR:?set OUTDIR}"
"$HERE/../lib/build.sh"
type python3 >/dev/null 2>&1 || { echo "needs python3" >&2; exit 2; }

PLATFORM=${PLATFORM:-ontario}
VARIANT=${VARIANT:-legion}
IN=$REPO/src/hypervisor/src/greatlakes/$PLATFORM/src/offsets.in
[ -f "$OUTDIR/offsets.h" ]     || { echo "FAIL: the build left no $OUTDIR/offsets.h" >&2; exit 1; }
[ -f "$OUTDIR/offsets.flags" ] || { echo "FAIL: no $OUTDIR/offsets.flags (written by build-offsets.sh)" >&2; exit 1; }
# shellcheck disable=SC1091
. "$OUTDIR/offsets.flags"                      # OPTS=, INC=

T=$OUTDIR/offsets-cross
rm -rf "$T"; mkdir -p "$T"
# word-splitting of $OPTS/$INC is intended: they are flag lists
# shellcheck disable=SC2086
python3 "$HERE/../lib/genoffsets.py" -o "$T/markers.h" --keep "$T/work" "$IN" -- $OPTS $INC 2> "$T/markers.err" \
    || { echo "FAIL: genoffsets.py did not run:" >&2; tail -5 "$T/markers.err" >&2; exit 1; }

vals() { grep -E '^#define[[:space:]]+[A-Za-z_0-9]+[[:space:]]+0x' "$1" | awk '{print $2, $3}' | sort; }
vals "$OUTDIR/offsets.h" > "$T/dwarf.vals"
vals "$T/markers.h"      > "$T/markers.vals"
join "$T/dwarf.vals" "$T/markers.vals" -o 1.1,1.2,2.2 > "$T/both.vals"
common=$(wc -l < "$T/both.vals")
bad=$(awk '$2 != $3' "$T/both.vals" | wc -l)
if [ "$bad" -ne 0 ]; then
    echo "FAIL: $bad symbol(s) differ between the DWARF reader and the compiler-evaluated markers (name, DWARF, markers):" >&2
    awk '$2 != $3' "$T/both.vals" | head -20 >&2
    exit 1
fi
if [ "$common" -lt 900 ]; then
    echo "FAIL: only $common symbols in common -- the comparison is too thin to mean anything (expected ~1000+)" >&2
    exit 1
fi
only_dwarf=$(join -v1 "$T/dwarf.vals" "$T/markers.vals" | wc -l)

ref=
if [ "$PLATFORM/$VARIANT" = "ontario/legion" ]; then
    R=$REPO/build/hv_reset/gnu/reference
    cmp -s "$OUTDIR/offsets.h"   "$R/offsets.ontario-legion.h"   || { echo "FAIL: offsets.h differs from the Sun-made reference" >&2; diff "$OUTDIR/offsets.h" "$R/offsets.ontario-legion.h" | head -10 >&2; exit 1; }
    cmp -s "$OUTDIR/offsets.chk" "$R/offsets.ontario-legion.chk" || { echo "FAIL: offsets.chk differs from the Sun-made reference" >&2; diff "$OUTDIR/offsets.chk" "$R/offsets.ontario-legion.chk" | head -10 >&2; exit 1; }
    ref="; offsets.h and offsets.chk are byte-identical to the Sun-made references"
fi

echo "ok: $common symbols agree between the DWARF reader and the compiler-evaluated markers (0 mismatches), $only_dwarf more only the reader makes$ref"
