# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# build-pci.sh -- sourced helper: build the pci config (niagara1-hw/release)
# into $OUTDIR/build once, idempotently. Several internal tests read
# artefacts from this same tree (dic-kernels.sh, dic-host.sh); when `run`
# gives them the same OUTDIR, only the first actually builds.
#
# Requires: OUTDIR, QEMU_SPARC32, QEMU_SPARC64, GNU (build/obp/gnu) already
# set by the caller. Defines: PCI_BUILD (the build tree), PCI_WORK (its
# obp/ root under its work directory, where every dictionary and dropin lands; PCI_WORKDIR is that
# work directory, $OUTDIR/work-pci).
build_pci_once() {
    PCI_BUILD=$OUTDIR/build
    PCI_WORKDIR=$OUTDIR/work-pci
    PCI_WORK=$PCI_WORKDIR/obp-gnu/niagara1-hw-release/obp
    if [ -f "$PCI_BUILD/openboot.bin" ]; then
        echo "-- reusing existing pci build at $PCI_BUILD --"
        return 0
    fi
    echo "=== building pci (niagara1-hw/release) into $PCI_BUILD ==="
    env OUTDIR="$PCI_BUILD" WORKDIR="$PCI_WORKDIR" "$GNU/build-obp.sh" niagara1-hw/release \
        > "$OUTDIR/build.log" 2>&1 \
        || { echo "FAIL: build -- see $OUTDIR/build.log" >&2; return 1; }
}
