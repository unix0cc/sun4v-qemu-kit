#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# build-obp.sh -- driver for obp-gnu.mk. Builds engine/host tools first
# (cached after the first run), then openboot.bin for the requested config.
# See build/obp/README.
#
# Usage: build-obp.sh [niagara/t1_fpga | niagara1-hw/release]
#
# Env:
#   OBP_GNU_REPO  source tree root (default: this script's own repo)
#   OUTDIR        where openboot.bin lands (default: $REPO/output -- same
#                 default obp-gnu.mk itself uses when OUTDIR is not passed).
#                 Point this outside the repo to keep it out of `git status`
#                 entirely.
#   WORKDIR       where the scratch build tree and the engine land, in
#                 obp-gnu/ (default: build/workdir.sh path $OUTDIR). Give each
#                 config its own OUTDIR (and so its own WORKDIR) to build them
#                 side by side.
#   ENGINE_OUT    where the cross-built engine and host tools land (default:
#                 $WORKDIR/obp-gnu/engine). Cached across runs; ~1.3 s to
#                 rebuild from clean. Kept out of the repo, so it never holds
#                 intermediate state.
#   REFERENCE_DIR mixed link: take decomp.o/version.fth/revlevel from
#                 this (reference build) directory, everything else ours. Then
#                 compare the product with `make obp-verify` (tests/full/obp).
#   OBP_PATCHES   if set (even empty), overrides obp-gnu.mk's list of
#                 patches/obp/forth/*.patch -- OBP_PATCHES= builds pristine
#                 Sun source, which is what obp-verify compares with Sun's
#                 own images.
#   QEMU_SPARC64  required, a qemu-sparc64 linux-user binary
#   QEMU_SPARC32  required, a qemu-sparc32plus linux-user binary (the 32-bit
#                 engine: dictionary bootstrap from forth.dic, tokenizer,
#                 fonts, logo)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${OBP_GNU_REPO:-$(cd "$HERE/../../.." && pwd)}"
OUTDIR="${OUTDIR:-$REPO/output}"

# The engines get paths under OUTDIR in their arguments and BP, and ask the kernel for their working directory (the Forth word
# getwd, a symlink is resolved): the LENGTH of those strings moves addresses that end up inside the dictionaries they save, and so
# openboot.bin. Same tree and inputs, a different image per length class of OUTDIR (measured 2026-10-07; the characters, the
# checkout path and the environment do not matter). So the build runs in a scratch directory of fixed length,
# /tmp/nfwobp.XXXXXX (/tmp, not TMPDIR: the length must not depend on the caller), and what the rest of the tree and the tests
# expect -- openboot.bin in OUTDIR, obp-gnu/<target> and the engine in WORKDIR -- is copied there when it is done. A relative OUTDIR works.
mkdir -p "$OUTDIR"
FINAL_OUT="$(cd "$OUTDIR" && pwd -P)"
FINAL_WORK="${WORKDIR:-$(sh "$REPO/build/workdir.sh" path "$FINAL_OUT")}"
SCRATCH="$(mktemp -d /tmp/nfwobp.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT
OUTDIR="$SCRATCH"
FINAL_ENGINE_OUT="${ENGINE_OUT:-}"
ENGINE_OUT="${ENGINE_OUT:-$OUTDIR/_tmp/obp-gnu/engine}"

CONFIG="${1:-niagara/t1_fpga}"
OBP_PLATFORM="${CONFIG%/*}"
OBP_TARGET="${CONFIG#*/}"

: "${QEMU_SPARC64:?set QEMU_SPARC64 to a qemu-sparc64 linux-user binary}"
: "${QEMU_SPARC32:?set QEMU_SPARC32 to a qemu-sparc32plus linux-user binary}"

# The engine and the host tools are built from the same inputs every time: keep them in WORKDIR (obp-gnu/engine) and take them from
# there while the inputs, the compilers and their flags are the ones they were built with. The key is the content of every input, not
# a timestamp. The engine is still built and run in the scratch directory (the length of its path moves addresses in the dictionaries,
# see above): a hit copies the finished tree there, with its times, and make finds nothing left to do.
engine_key() {
    ( cd "$REPO" && {
        find build/obp/gnu/engine -maxdepth 1 -type f -print0; find patches/obp/gnu -type f -print0
        for d in src/obp/tools src/obp/lib src/obp/include src/obp/obp/os/unix; do find "$d" -type f -print0; done
      } | LC_ALL=C sort -z | xargs -0 sha256sum
      echo "host-cc ${HOST_GCC:-gcc}: $(${HOST_GCC:-gcc} --version | sed 1q)"
      echo "cross-cc [${GNU_CSTD:-}]: $(sparc64-linux-gnu-gcc --version | sed 1q)" ) | sha256sum | cut -d' ' -f1
}
ENGINE_KEY="$(engine_key)"
ENGINE_CACHE="$FINAL_WORK/obp-gnu/engine"
if [ -z "$FINAL_ENGINE_OUT" ] && [ -f "$ENGINE_CACHE/.complete" ] && [ "$(cat "$ENGINE_CACHE/.key" 2>/dev/null)" = "$ENGINE_KEY" ]; then
    echo "=== engine + host tools: reusing $ENGINE_CACHE ==="
    mkdir -p "$(dirname "$ENGINE_OUT")"; cp -a "$ENGINE_CACHE" "$ENGINE_OUT"
else
    echo "=== engine + host tools ==="
fi
make -C "$HERE/engine" all OUT="$ENGINE_OUT" \
    OBP_SRC="$REPO/src/obp/obp" \
    TOOLS_SRC="$REPO/src/obp/tools" \
    INCLUDE_SRC="$REPO/src/obp/include" \
    LIB_SRC="$REPO/src/obp/lib" \
    GNU_PATCHES="$REPO/patches/obp/gnu"
printf '%s\n' "$ENGINE_KEY" > "$ENGINE_OUT/.key"; : > "$ENGINE_OUT/.complete"

PATCH_OVERRIDE=()
[ -n "${OBP_PATCHES+set}" ] && PATCH_OVERRIDE=(OBP_PATCHES="$OBP_PATCHES")

echo "=== openboot.bin ($OBP_PLATFORM/$OBP_TARGET) -> $OUTDIR ==="
make -f "$HERE/obp-gnu.mk" obp-gnu \
    QEMU_SPARC64="$QEMU_SPARC64" \
    QEMU_SPARC32="$QEMU_SPARC32" \
    OBP_PLATFORM="$OBP_PLATFORM" \
    OBP_TARGET="$OBP_TARGET" \
    REPO="$REPO" \
    OUTDIR="$OUTDIR" \
    ENGINE_OUT="$ENGINE_OUT" \
    REFERENCE_DIR="${REFERENCE_DIR:-}" \
    "${PATCH_OVERRIDE[@]}"

if [ -z "$FINAL_ENGINE_OUT" ]; then
    mkdir -p "$FINAL_WORK/obp-gnu"
    rm -rf "$FINAL_WORK/obp-gnu/engine"; cp -a "$SCRATCH/_tmp/obp-gnu/engine" "$FINAL_WORK/obp-gnu/engine"
fi
mkdir -p "$FINAL_WORK/obp-gnu"
rm -rf "$FINAL_WORK/obp-gnu/$OBP_PLATFORM-$OBP_TARGET"
cp -a "$SCRATCH/_tmp/obp-gnu/$OBP_PLATFORM-$OBP_TARGET" "$FINAL_WORK/obp-gnu/"
cp -p "$SCRATCH/openboot.bin" "$FINAL_OUT/openboot.bin"
echo "=== done: $FINAL_OUT/openboot.bin ==="
