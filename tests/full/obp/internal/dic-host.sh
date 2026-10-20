#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# dic-host.sh -- the host dictionaries a normal pci build bootstraps
# (forth32-xref.dic, f32t32.dic) against the copies Sun shipped in src/obp.
#
# Unlike the kernel dictionaries (dic-kernels.sh), these are not expected to
# be byte-identical, and comparing them raw is uninformative:
#
#   - Sun's own sun4v build recipe passes -D SUN4V to these steps
#     (niagara1-hw/release/Makefile:55, PLATFLAGS); bootstrap-dics.sh does
#     the same. The files Sun actually SHIPPED were saved without it, so
#     they lack one assembler word, rdver ([ifndef] SUN4V,
#     cpu/sparc/assem.fth:386-388) -- a deliberate, already-explained 20-byte
#     difference (TESTS, the Solaris bootstrap), not a defect.
#   - These are host dictionaries actually RUN by this build (not just
#     metacompiled), so they are also saved with a live user area and this
#     build's own dictionary origin -- the engine-binary-address class
#     (TESTS 5.2). Sun's shipped copies carry the addresses of Sun's native
#     engine; ours carry those of our cross-built forth32.
#
# The user area (the 8 KB data segment) is not waved through: a differing cell must be explained by the same corrections as the
# text, or be listed in expected/dic-user-area.<name>.txt (the engine-address and run-time cells); an unlisted one, or a listed one
# that stops differing, fails (dic-diff.py --user-pin).
#
# lib/dic-diff.py separates both effects from real content differences: it
# tries the entry-delta correction, and, for the rdver-sized shift, a
# byte-address and a call-word-count correction on either side of it, before
# calling anything left over unexplained. See its own header for the method.
#
# tokenize.dic is deliberately NOT compared here. It carries the same rdver
# shift plus several smaller ones from loadtok.fth's own conditionals, close
# enough together that dic-diff.py's per-region shift tracking does not
# cleanly separate them -- tried, and residual cells remain even with the
# global-shift candidate. Its correctness is established functionally
# instead: it tokenizes every dropin to output identical to Sun's (the
# didepend/makedi comparisons in TESTS, Appendix A) -- exactly the
# principle TESTS 5.2 already states for stand.dic/bootprom.bin ("never use
# a .dic hash as pass/fail; use products or execution"). Revisit if
# dic-diff.py's shift-tracking is ever made region-local instead of
# single-global.
#
# Env: QEMU_SPARC32, QEMU_SPARC64 (both required), OUTDIR (default: a
#      scratch dir under here; shared with dic-kernels.sh when `run` sets it).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)            # tests/full/obp/internal
REPO=$(cd "$HERE/../../../.." && pwd)
GNU=$REPO/build/obp/gnu
: "${QEMU_SPARC32:?set QEMU_SPARC32 to a qemu-sparc32plus linux-user binary}"
: "${QEMU_SPARC64:?set QEMU_SPARC64 to a qemu-sparc64 linux-user binary}"
export QEMU_SPARC32 QEMU_SPARC64
OUTDIR=${OUTDIR:-$(mktemp -d "${TMPDIR:-/tmp}/dic-host.XXXXXX")}
mkdir -p "$OUTDIR"
. "$REPO/tests/full/obp/lib/build-pci.sh"

echo "=== dic-host: host dictionaries from a pci build vs src/obp ==="
build_pci_once

bad=0
for f in os/sun/sparc/forth32-xref.dic os/sun/sparc/f32t32.dic; do
    if python3 "$REPO/tests/full/obp/lib/dic-diff.py" "$PCI_WORK/$f" "$REPO/src/obp/obp/$f" \
        --label-a "ours:$f" --label-b "shipped:$f" \
        --user-pin "$REPO/tests/full/obp/expected/dic-user-area.$(basename "$f" .dic).txt"; then
        :
    else
        bad=1
    fi
    echo
done

[ "$bad" = 0 ] || { echo "FAIL: dic-host"; exit 1; }
echo "PASS: dic-host -- forth32-xref.dic and f32t32.dic differ from Sun's shipped"
echo "      copies only by the known rdver shift, entry-delta rebasing, and the"
echo "      pinned engine-binary/user-area cells (see this script's header)"
