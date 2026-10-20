#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# sun-records-regenerate.sh -- rewrite expected/sun-records.sha256 and
# expected/dict-dump.sha256 from a fresh build and Sun's own two shipped
# images (niagara2/release, niagara/t1_fpga) inside
# OpenSPARCT2_Arch.1.2.tar.bz2.
#
# Run this after a change to src/obp, not routinely -- internal/sun-records.sh
# and internal/dict-content.sh already check against the committed files
# without needing the tarball at all. Review the diff before committing:
# regenerating silently accepts whatever the working tree currently
# produces, which is only right if that tree is known-good.
#
# Usage: sun-records-regenerate.sh <OpenSPARCT2_Arch.1.2.tar.bz2>
#        (or set OPENSPARC_T2 to the path and omit the argument)
# Env:   QEMU_SPARC32, QEMU_SPARC64 (both required).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)            # tests/full/obp/external
REPO=$(cd "$HERE/../../../.." && pwd)
GNU=$REPO/build/obp/gnu
LIB=$REPO/tests/full/obp/lib
EXPECTED=$REPO/tests/full/obp/expected
TARBALL=${1:-${OPENSPARC_T2:-}}
[ -n "$TARBALL" ] || { echo "usage: $0 <OpenSPARCT2_Arch.1.2.tar.bz2>  (or set OPENSPARC_T2)" >&2; exit 2; }
[ -f "$TARBALL" ] || { echo "FAIL: $TARBALL not found" >&2; exit 1; }
: "${QEMU_SPARC32:?set QEMU_SPARC32 to a qemu-sparc32plus linux-user binary}"
: "${QEMU_SPARC64:?set QEMU_SPARC64 to a qemu-sparc64 linux-user binary}"
export QEMU_SPARC32 QEMU_SPARC64
OUTDIR=$(mktemp -d "${TMPDIR:-/tmp}/sun-records-regen.XXXXXX")
trap 'rm -rf "$OUTDIR"' EXIT

SUN_TARGETS="niagara2/release niagara/t1_fpga"

echo "=== extracting Sun's two shipped openboot.bin from $(basename "$TARBALL") ==="
T=$OUTDIR/tarball
mkdir -p "$T"
for t in $SUN_TARGETS; do
    tar xjf "$TARBALL" -C "$T" "./obp/obp/arch/sun4v/$t/openboot.bin"
done

{
    echo "# Sun's own openboot.bin records, from $(basename "$TARBALL")"
    echo "# (sha256 $(sha256sum "$TARBALL" | cut -c1-64))."
    for t in $SUN_TARGETS; do
        f=$T/obp/obp/arch/sun4v/$t/openboot.bin
        echo "# $t/openboot.bin: $(stat -c %s "$f") B, sha256 $(sha256sum "$f" | cut -c1-64)"
    done
    echo "# '-' = compared by name and position only (TESTS section 5). Regenerate:"
    echo "#   tests/full/obp/external/sun-records-regenerate.sh <tarball>"
    for t in $SUN_TARGETS; do
        python3 "$LIB/records.py" "$T/obp/obp/arch/sun4v/$t/openboot.bin" "$t"
    done
} > "$EXPECTED/sun-records.sha256"

echo "=== building pci (patched) for dict-content ==="
. "$LIB/build-pci.sh"
build_pci_once
FORTH64_BIN=$PCI_WORKDIR/obp-gnu/engine/forth64
"$LIB/dict-dump.sh" "$PCI_WORK/arch/sun4v/niagara1-hw/release/stand.dic" \
    > "$OUTDIR/dict-dump.txt" 2>/dev/null
( cd "$OUTDIR" && sha256sum dict-dump.txt ) > "$EXPECTED/dict-dump.sha256"

echo "wrote $EXPECTED/sun-records.sha256 ($(grep -vc '^#' "$EXPECTED/sun-records.sha256") records)" \
     "+ dict-dump.sha256"
echo "review with: git -C $REPO diff -- tests/full/obp/expected"
