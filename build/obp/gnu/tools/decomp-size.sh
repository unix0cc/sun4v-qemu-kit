#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# decomp-size.sh -- GNU equivalent of the Solaris pipeline
#   size -f decomp.o | sed -e 's/+/ /g' -e 's/(./ /g' -e 's/)//g' | nawk -f getsz.awk
# computing decomp-size = .text + .bss + .data for the reset.o build's
# embedded "d# <N> constant decomp-size" line (arch/sun4v/common.mk).
#
# getsz.awk itself needs no change (it was never wrong) --
# only the "size -f" front end differs between Solaris and GNU binutils.
# GNU size's plain "-A" output already gives .text/.data/.bss as separate
# named lines, so this is a direct sum, not a port of the awk script.
set -eu
OBJ="${1:?usage: decomp-size.sh <decomp.o>}"
SIZE_BIN="${SPARC64_SIZE:-sparc64-linux-gnu-size}"
"$SIZE_BIN" -A "$OBJ" | awk '
    $1 == ".text" || $1 == ".data" || $1 == ".bss" { sum += $2 }
    END { print sum }
'
