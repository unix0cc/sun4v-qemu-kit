#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# sun-records.sh -- pristine builds of the two targets Sun shipped an image
# of, niagara2/release (Sun's 2007 build) and niagara/t1_fpga (Sun's 2009
# image), reproduce every dropin record of Sun's own images.
#
# Walked record by record against expected/sun-records.sha256 (committed):
# same record names in the same order, every record's sha256 equal to
# Sun's. Not compared, by design, both here and in that file ('-'): OBP
# (decomp.o is compiled by a different C compiler) and bootprom (the saved
# Forth image carries the engine binary's own addresses) -- see TESTS
# section 4 and dic-host.sh's header for that class of difference.
#
# This is the internal half: it needs no tarball, only the committed hash
# file. external/sun-records-regenerate.sh re-derives that file from
# OpenSPARCT2_Arch.1.2.tar.bz2 and is how a change to src/obp gets a
# reviewed update to it -- run that one after any src/obp change, not this.
#
# Env: QEMU_SPARC32, QEMU_SPARC64 (both required), OUTDIR (default: a
#      scratch dir under here).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)            # tests/full/obp/internal
REPO=$(cd "$HERE/../../../.." && pwd)
GNU=$REPO/build/obp/gnu
LIB=$REPO/tests/full/obp/lib
EXPECTED=$REPO/tests/full/obp/expected/sun-records.sha256
: "${QEMU_SPARC32:?set QEMU_SPARC32 to a qemu-sparc32plus linux-user binary}"
: "${QEMU_SPARC64:?set QEMU_SPARC64 to a qemu-sparc64 linux-user binary}"
export QEMU_SPARC32 QEMU_SPARC64
OUTDIR=${OUTDIR:-$(mktemp -d "${TMPDIR:-/tmp}/sun-records.XXXXXX")}
mkdir -p "$OUTDIR"
[ -f "$EXPECTED" ] || { echo "FAIL: $EXPECTED missing -- run external/sun-records-regenerate.sh first" >&2; exit 1; }

SUN_TARGETS="niagara2/release niagara/t1_fpga"

echo "=== sun-records: pristine builds vs $EXPECTED ==="
: > "$OUTDIR/ours.txt"
for t in $SUN_TARGETS; do
    sub=pristine-${t%/*}
    rm -rf "$OUTDIR/$sub"
    env OBP_PATCHES= OUTDIR="$OUTDIR/$sub" WORKDIR="$OUTDIR/work-$sub" "$GNU/build-obp.sh" "$t" \
        > "$OUTDIR/$sub.log" 2>&1 \
        || { echo "FAIL: build $t (pristine) -- see $OUTDIR/$sub.log" >&2; exit 1; }
    python3 "$LIB/records.py" "$OUTDIR/$sub/openboot.bin" "$t" >> "$OUTDIR/ours.txt"
done

if diff <(grep -v '^#' "$EXPECTED") "$OUTDIR/ours.txt" > "$OUTDIR/records.diff"; then
    n=$(grep -vc '^#' "$EXPECTED")
    hashed=$(grep -vc '^-  ' "$OUTDIR/ours.txt")
    echo "PASS: sun-records -- $n records present in Sun's order, $hashed hashed and" \
         "identical to Sun's (OBP, bootprom compared by name/position only)"
else
    echo "FAIL: sun-records" >&2; cat "$OUTDIR/records.diff" >&2; exit 1
fi
