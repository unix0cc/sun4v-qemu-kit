#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# toolchain-check.sh <OUTDIR> <HOST_GCC> <QEMU_SPARC64> <QEMU_SPARC32> <GNU_CSTD> <HOST_CSTD> <WORKDIR> <SRC>
#
# The gnu path only. Output of one toolchain must not be mixed with output of another: the rules know the sources,
# not the compiler that built an object, so `make` after a switch of distribution (Debian's gcc 14 against Ubuntu's 13,
# say) would keep the old objects. This writes the identity of the tools to $OUTDIR/.toolchain, and when an OUTDIR that
# holds output was built with other tools (or with no record), removes it and the work directory, as `make clean` would, and says so.
# Called by the Makefile at parse time for every goal that builds; never for clean, config or help.
OUT=$1; HOSTGCC=$2; Q64=$3; Q32=$4; GCST=$5; HCST=$6; WORK=${7:-}; SRC=${8:-}
case "$OUT" in ""|/|"$HOME"|"$HOME"/) echo "toolchain-check: refusing OUTDIR=$OUT" >&2; exit 0;; esac
ver() { "$@" --version 2>/dev/null | sed -n 1p; }
ID=$(
    echo "cross-gcc  $(ver sparc64-linux-gnu-gcc)"
    echo "cross-ld   $(ver sparc64-linux-gnu-ld)"
    echo "host-gcc   $(ver "$HOSTGCC")"
    echo "qemu-user  $(ver "$Q64") / $(ver "$Q32")"
    echo "cstd       cross:$GCST host:$HCST"
)
REC=$OUT/.toolchain
if [ -f "$REC" ] && [ "$(cat "$REC")" = "$ID" ]; then exit 0; fi
if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then
    if [ -f "$REC" ]; then why="other tools than the ones recorded in $REC"; else why="no record of the tools it was built with"; fi
    {   echo "toolchain-check: $OUT holds output built with $why; removing it and building again."
        [ -f "$REC" ] && { echo "  was:"; sed 's/^/    /' "$REC"; echo "  now:"; echo "$ID" | sed 's/^/    /'; }
    } >&2
    rm -rf "$OUT"
    [ -z "$WORK" ] || sh "$(dirname "$0")/workdir.sh" clean "$WORK" "$SRC" >&2
fi
mkdir -p "$OUT" && printf '%s\n' "$ID" > "$REC"
exit 0
