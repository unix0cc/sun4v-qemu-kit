#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# build.sh -- build the GNU hypervisor once, with the assembler's and the compiler's stderr VISIBLE.
#
# build/hv_reset/gnu/build.sh assembles and compiles with `2>/dev/null`, so a warning never reaches any
# log and a failed file is reduced to one `ASM FAIL <file>` line. The tests here need the text, so this
# runs the very same script with that redirection removed. `$0` is kept as the real path, so the script
# still finds its own directory and the repo root.
#
# Shared: if $OUTDIR already holds a finished build (q.elf, offsets.flags), it is reused, so `run` builds once for all
# the tests. REBUILD=1 forces a fresh one.
#
# Env: OUTDIR   where to build (required)
#      PLATFORM, VARIANT   default ontario / legion, what build.sh defaults to
#      HV_EXTRA_OPTS       the -D/-U list; `make hv-verify` passes the same one `make hv_reset` uses. The
#                          default below is HV_OPTIONS from config.mk -- keep it in step.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)   # repo root
: "${OUTDIR:?set OUTDIR}"
B=$HERE/build/hv_reset/gnu/build.sh

# offsets.flags is what offsets-cross-check needs; a build from before it existed is rebuilt
if [ -f "$OUTDIR/q.elf" ] && [ -f "$OUTDIR/offsets.flags" ] && [ "${REBUILD:-0}" != 1 ]; then exit 0; fi
type sparc64-linux-gnu-gcc >/dev/null 2>&1 || { echo "hv_reset tests need the sparc64-linux-gnu cross toolchain" >&2; exit 2; }

# rm -rf below: only the directory of an earlier run of this script (it holds build.log), an empty one, or one to be made
if [ -d "$OUTDIR" ] && [ -n "$(ls -A "$OUTDIR")" ] && [ ! -f "$OUTDIR/build.log" ]; then
    echo "hv_reset tests: refusing OUTDIR=$OUTDIR: it is not empty and not the output of an earlier run (no build.log)" >&2; exit 2
fi
_real=$(cd "$OUTDIR" 2>/dev/null && pwd) || _real=$OUTDIR
case "$_real" in /|"$HOME"|"") echo "hv_reset tests: refusing OUTDIR=$OUTDIR" >&2; exit 2;; esac
case "$HERE/" in "$_real"/*) echo "hv_reset tests: refusing OUTDIR=$OUTDIR: it holds the repository" >&2; exit 2;; esac
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"
export HV_EXTRA_OPTS="${HV_EXTRA_OPTS--UFOR_ZEUS -UCONFIG_LEGIONBCOPY -UDEBUG_LEGION -URESETCONFIG_BROKENTICK -UCONFIG_HVUART}"
[ -n "${PLATFORM:-}" ] && export PLATFORM
[ -n "${VARIANT:-}" ] && export VARIANT

if ! sh -c "$(sed 's| 2>/dev/null||' "$B")" "$B" "$OUTDIR" > "$OUTDIR/build.log" 2>&1 || [ ! -f "$OUTDIR/q.elf" ]; then
    echo "FAIL: the GNU hypervisor build did not finish; last lines of $OUTDIR/build.log:" >&2
    tail -15 "$OUTDIR/build.log" >&2
    exit 1
fi
