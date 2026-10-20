#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# dic-fixpoint.sh -- second-generation bootstrap fixpoint, on Linux.
#
# Every normal build already checks the FIRST-generation fixpoint as a
# build-time assertion (bootstrap-dics.sh: kernel-xref == k32t32-xref, from
# Sun's own forth.dic root) -- that is inherent to dic-kernels.sh's build
# succeeding at all, per Sun's own depend.mk:177-180 offering the -xref
# models as forth.dic replacements. What that does NOT check is whether the
# chain is a fixpoint from a SECOND root: take gen1's own forth32-xref.dic,
# use it AS forth.dic, and bootstrap again. If the chain really has reached
# a fixed point, gen2 must reproduce gen1 exactly and gen2's own
# forth32-xref.dic must equal the root it was built from -- proven on
# Solaris with Sun's own engine (TESTS, the Solaris bootstrap: gen1b/gen2),
# never repeated on the cross-built engine until this test.
#
# Env: QEMU_SPARC32 (required), OUTDIR (default: a scratch dir under here).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)            # tests/full/obp/internal
REPO=$(cd "$HERE/../../../.." && pwd)
GNU=$REPO/build/obp/gnu
: "${QEMU_SPARC32:?set QEMU_SPARC32 to a qemu-sparc32plus linux-user binary}"
: "${QEMU_SPARC64:?set QEMU_SPARC64 to a qemu-sparc64 linux-user binary}"
export QEMU_SPARC32 QEMU_SPARC64
OUTDIR=${OUTDIR:-$(mktemp -d "${TMPDIR:-/tmp}/dic-fixpoint.XXXXXX")}
mkdir -p "$OUTDIR"
ENGINE_OUT=$OUTDIR/engine

echo "=== dic-fixpoint: build the 32-bit engine ==="
make -C "$GNU/engine" all OUT="$ENGINE_OUT" \
    OBP_SRC="$REPO/src/obp/obp" TOOLS_SRC="$REPO/src/obp/tools" \
    INCLUDE_SRC="$REPO/src/obp/include" LIB_SRC="$REPO/src/obp/lib" \
    GNU_PATCHES="$REPO/patches/obp/gnu" > "$OUTDIR/engine.log" 2>&1 \
    || { echo "FAIL: engine build -- see $OUTDIR/engine.log" >&2; exit 1; }
export FORTH32_BIN=$ENGINE_OUT/forth32

BOOTSTRAP="$GNU/tools/bootstrap-dics.sh"
U=os/sun/sparc
K=fm/kernel/sparc
T=pkg/tokenizr/sparc

echo "=== dic-fixpoint: generation 1 -- Sun's own forth.dic ==="
GEN1=$OUTDIR/gen1/obp
mkdir -p "$(dirname "$GEN1")"
cp -a "$REPO/src/obp/obp" "$GEN1"
"$BOOTSTRAP" "$GEN1" > "$OUTDIR/gen1.log" 2>&1 \
    || { echo "FAIL: gen1 bootstrap -- see $OUTDIR/gen1.log" >&2; exit 1; }

echo "=== dic-fixpoint: generation 2 -- gen1's forth32-xref.dic as the root ==="
GEN2=$OUTDIR/gen2/obp
mkdir -p "$(dirname "$GEN2")"
cp -a "$REPO/src/obp/obp" "$GEN2"
cp "$GEN1/$U/forth32-xref.dic" "$GEN2/$U/forth.dic"
"$BOOTSTRAP" "$GEN2" > "$OUTDIR/gen2.log" 2>&1 \
    || { echo "FAIL: gen2 bootstrap -- see $OUTDIR/gen2.log" >&2; exit 1; }

bad=0
echo "-- gen2's own forth32-xref.dic vs the root it was built from (fixpoint) --"
if cmp -s "$GEN2/$U/forth32-xref.dic" "$GEN2/$U/forth.dic"; then
    echo "  identical -- the chain reproduces its own root"
else
    echo "  DIFFERENT -- not a fixpoint"; bad=1
fi

echo "-- gen2 vs gen1, every dictionary and listing (no drift across generations) --"
for f in "$K/kernel-xref.dic" "$K/k32t32-xref.dic" "$K/k64t32.dic" \
         "$U/forth32-xref.dic" "$U/f32t32.dic" "$T/tokenize.dic" \
         "$K/kernel-xref.fth" "$K/kernel-xref.headless.fth" \
         "$K/k32t32-xref.fth" "$K/k32t32-xref.headless.fth" \
         "$K/k64t32.fth" "$K/k64t32.headless.fth"; do
    if cmp -s "$GEN1/$f" "$GEN2/$f"; then
        echo "  identical  $f"
    else
        echo "  DIFFERENT  $f"; bad=1
    fi
done

[ "$bad" = 0 ] || { echo "FAIL: dic-fixpoint"; exit 1; }
echo "PASS: dic-fixpoint -- gen2 reproduces its own root and matches gen1 throughout"
