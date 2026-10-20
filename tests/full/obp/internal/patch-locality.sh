#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# patch-locality.sh -- this project's four patches/obp/forth/*.patch touch
# only three dropins: ide-srst-no-bsy-check.patch and the two ophir patches
# touch obp/dev/ide/pci and obp/dev/network/ophir, each its own OBMD dropin
# (ophir, class010100 -- the pci config's dropin names, per
# src/obp/obp/arch/sun4v/niagara1-hw/release/dropins.src). The fourth,
# md-iodevice-reg-guard.patch, touches arch/sun4v/md-iodevice-props.fth --
# core Forth source, part of builtin.fth, which ends up INSIDE the
# bootprom record (the saved, tokenized dictionary image), not the separate
# OBP record -- confirmed the other way round too: OBP embeds version.fth's
# stamp (an intermediate reset.o carries the record's OBMD header directly,
# e.g. bytes 09 1a 15 17 = month/day/hour/minute; save-obj copies it from
# compile-signature, TESTS 5.4), so it differs between any two builds whose
# stamps differ, regardless of patches. The two builds here run from one
# tree at different times, and a dirty tree stamps the build time, so in
# practice they do. bootprom is excluded from byte comparison for its own, unrelated
# reason (the engine-binary-address class, TESTS 5.2). Between the build-
# timestamp class and the engine-binary class, this test CANNOT confirm
# md-iodevice-reg-guard.patch's locality the way it confirms the other
# three -- only that it did not leak into some OTHER dropin. Noted as a
# limitation, not silently assumed away.
#
# Building the pci config pristine (OBP_PATCHES=, no patches) and patched
# (the default) must differ in exactly: OBP (unscored -- see above; may or
# may not match depending only on whether the two builds landed in the same
# minute), bootprom (unscored, the accepted class), and the two device dropins.
# Every other dropin -- vpci, the console/vnet/vdisk/tod/flashprom/chan-dev
# family, fonts, sunlogo, both support-pkg instances, usbkbds, su-serial,
# bge, the USB/keyboard family -- must be byte-identical to the pristine
# build.
#
# This is the complement to sun-records.sh: that test proves the pristine
# build matches Sun; this one proves the product build's patches change
# only what they say they change, nothing else (net of the bootprom
# limitation above). Needs no tarball -- both builds are ours.
#
# Also checked: ophir and class010100 must actually DIFFER between the two
# builds. If they did not, either the patches are no-ops or something else
# is wrong with this test -- either way "identical everywhere" would be a
# false pass, not a stronger result.
#
# Env: QEMU_SPARC32, QEMU_SPARC64 (both required), OUTDIR (default: a
#      scratch dir under here).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)            # tests/full/obp/internal
REPO=$(cd "$HERE/../../../.." && pwd)
GNU=$REPO/build/obp/gnu
LIB=$REPO/tests/full/obp/lib
: "${QEMU_SPARC32:?set QEMU_SPARC32 to a qemu-sparc32plus linux-user binary}"
: "${QEMU_SPARC64:?set QEMU_SPARC64 to a qemu-sparc64 linux-user binary}"
export QEMU_SPARC32 QEMU_SPARC64
OUTDIR=${OUTDIR:-$(mktemp -d "${TMPDIR:-/tmp}/patch-locality.XXXXXX")}
mkdir -p "$OUTDIR"
. "$REPO/tests/full/obp/lib/build-pci.sh"

# The dropins this project's patches are allowed to touch, plus the two
# records excluded from byte comparison everywhere in this test suite for
# reasons that have nothing to do with patches at all.
ALLOWED_DIFF="OBP bootprom ophir class010100"

echo "=== patch-locality: pristine vs patched pci build ==="
build_pci_once   # patched (default OBP_PATCHES)

PRISTINE=$OUTDIR/pristine
rm -rf "$PRISTINE"
env OBP_PATCHES= OUTDIR="$PRISTINE" WORKDIR="$OUTDIR/work-pristine" "$GNU/build-obp.sh" niagara1-hw/release \
    > "$OUTDIR/pristine.log" 2>&1 \
    || { echo "FAIL: pristine build -- see $OUTDIR/pristine.log" >&2; exit 1; }

bad=0
python3 - "$PCI_BUILD/openboot.bin" "$PRISTINE/openboot.bin" "$ALLOWED_DIFF" "$LIB" <<'EOF' || bad=1
import sys
sys.path.insert(0, sys.argv[4])
from records import walk

patched_path, pristine_path, allowed = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
# Record names are not unique within one image (measured: the pci
# config carries two distinct "support-pkg" records) -- compare by POSITION,
# which also catches a reordering that a name-keyed comparison would miss.
patched  = [(name, rec) for name, _, rec in walk(patched_path)]
pristine = [(name, rec) for name, _, rec in walk(pristine_path)]

bad = False
if len(patched) != len(pristine) or [n for n, _ in patched] != [n for n, _ in pristine]:
    print(f"  RECORD ORDER/COUNT MISMATCH: patched {[n for n,_ in patched]}")
    print(f"                              pristine {[n for n,_ in pristine]}")
    sys.exit(1)

# OBP and bootprom are allowed to differ (or not) for reasons unrelated to
# these patches (decomp.o codegen; the engine-binary-address class) -- only
# the two device dropins are actually asserted to change.
DEVICE_DROPINS = allowed - {"OBP", "bootprom"}
seen = {}   # name -> occurrence count so far, for a readable label on repeats
unexpected_diff, unexpected_same = [], []
for (name, prec), (_, orec) in zip(patched, pristine):
    seen[name] = seen.get(name, 0) + 1
    label = name if seen[name] == 1 else f"{name} #{seen[name]}"
    same = prec == orec
    if name in allowed:
        status = "differs (allowed)" if not same else "identical (unscored: OBP/bootprom)"
        if same and name in DEVICE_DROPINS:
            status = "IDENTICAL (unexpected -- patch had no effect?)"
            unexpected_same.append(label)
    else:
        status = "identical" if same else "DIFFERS (not in the allowed set)"
        if not same:
            unexpected_diff.append(label)
    print(f"  {label}: {status}")

if unexpected_diff:
    print(f"  UNEXPECTED: {unexpected_diff} differ but are not in the allowed set {sorted(allowed)}")
    bad = True
if unexpected_same:
    print(f"  UNEXPECTED: {unexpected_same} are byte-identical despite being patched -- "
          "the patch may not have taken effect")
    bad = True

sys.exit(1 if bad else 0)
EOF

[ "$bad" = 0 ] || { echo "FAIL: patch-locality"; exit 1; }
echo "PASS: patch-locality -- only ophir and class010100 differ from the pristine" \
     "build (plus OBP/bootprom, excluded for unrelated reasons); every other" \
     "dropin is byte-identical"
