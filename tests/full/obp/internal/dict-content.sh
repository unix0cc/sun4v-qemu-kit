#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# dict-content.sh -- the pci build's stand.dic word list (every word in
# every vocabulary: forth/hidden/keys-forth/decompressor/assembler/root, via
# the dictionary's own `words`) against expected/dict-dump.sha256.
#
# This is a regression check on OUR OWN output, not a comparison with Sun --
# unlike sun-records.sh and patch-locality.sh, nothing here is independently
# derived from Sun's images or from a pristine/patched pair. It exists
# because a stand.dic/bootprom.bin byte hash is useless as a pass/fail
# criterion by construction (TESTS 5.2: every saved image differs by
# engine-binary addresses on any legitimate rebuild) but the WORD NAMES
# defined do not move on a harmless recompile -- only on a real content
# change dict-diff.py's classes cannot explain, which is exactly what
# sun-records.sh and patch-locality.sh already isolate more precisely (one
# against Sun's own images, the other against a pristine build of the same
# source). Kept as a cheap, independent third check on the same claim.
#
# Env: QEMU_SPARC32, QEMU_SPARC64 (both required), OUTDIR (default: a
#      scratch dir under here).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)            # tests/full/obp/internal
REPO=$(cd "$HERE/../../../.." && pwd)
GNU=$REPO/build/obp/gnu
LIB=$REPO/tests/full/obp/lib
EXPECTED=$REPO/tests/full/obp/expected/dict-dump.sha256
: "${QEMU_SPARC32:?set QEMU_SPARC32 to a qemu-sparc32plus linux-user binary}"
: "${QEMU_SPARC64:?set QEMU_SPARC64 to a qemu-sparc64 linux-user binary}"
export QEMU_SPARC32 QEMU_SPARC64
OUTDIR=${OUTDIR:-$(mktemp -d "${TMPDIR:-/tmp}/dict-content.XXXXXX")}
mkdir -p "$OUTDIR"
. "$REPO/tests/full/obp/lib/build-pci.sh"

echo "=== dict-content: pci build's stand.dic word list vs $EXPECTED ==="
build_pci_once

FORTH64_BIN=$PCI_WORKDIR/obp-gnu/engine/forth64
[ -x "$FORTH64_BIN" ] || FORTH64_BIN=$(find "$OUTDIR" -name forth64 -type f | head -1)
[ -x "$FORTH64_BIN" ] || { echo "FAIL: forth64 engine binary not found under $OUTDIR" >&2; exit 1; }

FORTH64_BIN="$FORTH64_BIN" "$LIB/dict-dump.sh" \
    "$PCI_WORK/arch/sun4v/niagara1-hw/release/stand.dic" \
    > "$OUTDIR/dict-dump.txt" 2>/dev/null

if ( cd "$OUTDIR" && sha256sum -c "$EXPECTED" --quiet ); then
    echo "PASS: dict-content -- word list matches"
else
    echo "FAIL: dict-content"; exit 1
fi
