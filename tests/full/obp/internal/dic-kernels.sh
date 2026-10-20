#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# dic-kernels.sh -- the three kernel dictionaries a normal pci build
# bootstraps from forth.dic (kernel-xref, k32t32-xref, k64t32) must equal
# the copies Sun shipped in src/obp byte for byte, and the six word listings
# (.fth, .headless.fth) must match line for line below the copyright banner
# Sun's 2009 packaging prepended to generated files too.
#
# This is the first and strongest claim in the chain: these three
# dictionaries need no reconciliation at all (unlike the host dictionaries,
# dic-host.sh) because they are pure KERNEL saves (bootstrap-dics.sh's -F
# flag) with no live user area and an identical entry/origin to Sun's own --
# see dic-host.sh's header for what that class of difference is and why it
# does not apply here.
#
# Env: QEMU_SPARC32, QEMU_SPARC64 (both required), OUTDIR (default: a
#      scratch dir under here; shared with dic-host.sh when `run` sets it).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)            # tests/full/obp/internal
REPO=$(cd "$HERE/../../../.." && pwd)
GNU=$REPO/build/obp/gnu
: "${QEMU_SPARC32:?set QEMU_SPARC32 to a qemu-sparc32plus linux-user binary}"
: "${QEMU_SPARC64:?set QEMU_SPARC64 to a qemu-sparc64 linux-user binary}"
export QEMU_SPARC32 QEMU_SPARC64
OUTDIR=${OUTDIR:-$(mktemp -d "${TMPDIR:-/tmp}/dic-kernels.XXXXXX")}
mkdir -p "$OUTDIR"
. "$REPO/tests/full/obp/lib/build-pci.sh"

echo "=== dic-kernels: kernels from a pci build vs src/obp ==="
build_pci_once

W=$PCI_WORK/fm/kernel/sparc
S=$REPO/src/obp/obp/fm/kernel/sparc
bad=0
for k in kernel-xref k32t32-xref k64t32; do
    if cmp -s "$W/$k.dic" "$S/$k.dic"; then
        echo "  identical  $k.dic"
    else
        echo "  DIFFERENT  $k.dic"; bad=1
    fi
    for l in "$k.fth" "$k.headless.fth"; do
        n=$(grep -n "Copyright Header End" "$S/$l" | cut -d: -f1)
        if tail -n +$((${n:-0} + 1)) "$S/$l" | cmp -s - "$W/$l"; then
            echo "  identical  $l (below Sun's banner)"
        else
            echo "  DIFFERENT  $l"; bad=1
        fi
    done
done

[ "$bad" = 0 ] || { echo "FAIL: dic-kernels"; exit 1; }
echo "PASS: dic-kernels -- 3 kernels byte-identical, 6 listings identical to Sun's"
