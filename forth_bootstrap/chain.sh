#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# chain.sh -- the whole OBP dictionary chain from the cforth-derived step 1, with no forth.dic and none of Sun's kernel-xref files read:
#   check-seed.sh (cforth)  ->  bootstrap-dics.sh with OBP_SEED=kernel-xref and OBP_SEED_DIR=$FB_WORK/seed-cf
# bootstrap-dics.sh builds from that directory forth32-xref, k32t32-xref, f32t32, k64t32,
# tokenize on the -m32 engine under qemu-sparc32plus, and asserts the fixpoint kernel-xref == k32t32-xref.
#   Env: FB_WORK, QEMU_SPARC32 (default qemu-sparc32plus-static in PATH). Exit 77 = skip.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/.." && pwd)
. "$HERE/fbwork.sh"
export QEMU_SPARC32=${QEMU_SPARC32:-$(command -v qemu-sparc32plus-static || true)}
export QEMU_SPARC64=${QEMU_SPARC64:-$(command -v qemu-sparc64-static || true)}
[ -n "$QEMU_SPARC32" ] || { echo "SKIP: no qemu-sparc32plus linux-user binary" >&2; exit 77; }
"$HERE/check-seed.sh"
G=$REPO/build/obp/gnu
make -C "$G/engine" all OUT="$W/engine" OBP_SRC="$REPO/src/obp/obp" TOOLS_SRC="$REPO/src/obp/tools" \
    INCLUDE_SRC="$REPO/src/obp/include" LIB_SRC="$REPO/src/obp/lib" GNU_PATCHES="$REPO/patches/obp/gnu" >"$W/engine.log" 2>&1 \
    || { echo "chain: engine build failed, see $W/engine.log" >&2; exit 1; }
export FORTH32_BIN=$W/engine/forth32
rm -rf "$W/chain"; mkdir -p "$W/chain"; cp -a "$REPO/src/obp/obp" "$W/chain/obp"
OBP_SEED=kernel-xref OBP_SEED_DIR=$W/seed-cf "$G/tools/bootstrap-dics.sh" "$W/chain/obp" >"$W/chain.log" 2>&1 \
    || { echo "chain: bootstrap failed, see $W/chain.log" >&2; tail -5 "$W/chain.log" >&2; exit 1; }
echo "chain: forth32-xref, k32t32-xref, f32t32, k64t32, tokenize built from the cforth-derived seed; fixpoint held"
cat "$W/chain.log" | tail -3
