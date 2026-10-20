#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# The reference. Sun's own OpenSPARC T1 config sources, run through the chain this repository uses
# (GNU cpp -traditional-cpp + our mdgen), must reproduce Sun's SHIPPED binaries byte for byte; and each
# shipped binary must unfold and refold to itself. Six binaries: 1up, 1g2p, 1g32p, guest and hv.
# If this fails, nothing else in tests/full/md means anything: the toolchain does not compile MD the way Sun did.
. "$(dirname "$0")/../lib/env.sh"
SRC=$T1/legion/src/config/niagara; SHIP=$T1/S10image
need "$SRC/1up.pdesc" "OpenSPARC T1 tree, set T1="
# The reference tree must be the pristine one: Sun's eight config sources and twelve shipped binaries, by hash (no Sun text is stored here).
for f in sun-t1-sources sun-t1-binaries; do
    (cd "$T1" && sha256sum -c --quiet "$HERE/expected/$f.sha256") \
        || { echo "FAIL: the reference tree $T1 is not the pristine OpenSPARC T1 ($f.sha256 does not match)" >&2; exit 1; }
done
echo "ok  reference tree pristine: 8 sources and 12 binaries match expected/sun-t1-*.sha256"
build_ours
n=0
for cfg in 1up 1g2p 1g32p; do
  for k in pdesc:md hdesc:hv; do
    e=${k%:*}; t=${k#*:}; w=$OUT/ref-$cfg-$t
    $CPP "$SRC/$cfg.$e" "$w.pp"
    "$MDGEN" --binary --outfile "$w.bin" "$w.pp"
    cmp "$w.bin" "$SHIP/$cfg-$t.bin" || { echo "FAIL: $cfg-$t: rebuild differs from Sun's shipped binary" >&2; exit 1; }
    python3 "$UNFOLD" "$SHIP/$cfg-$t.bin" > "$w.unf"
    "$MDGEN" --binary --outfile "$w.re.bin" "$w.unf"
    cmp "$w.re.bin" "$SHIP/$cfg-$t.bin" || { echo "FAIL: $cfg-$t: unfold+refold of Sun's binary differs" >&2; exit 1; }
    python3 "$UNFOLD" "$w.re.bin" | cmp - "$w.unf" || { echo "FAIL: $cfg-$t: unfolded text is not a fixpoint" >&2; exit 1; }
    "$MDLINT" "$SHIP/$cfg-$t.bin" > "$w.lint" 2>&1 && [ ! -s "$w.lint" ] || { echo "FAIL: $cfg-$t: mdlint does not accept Sun's shipped binary: $(head -1 "$w.lint")" >&2; exit 1; }
    echo "ok  $cfg-$t  $(sha256sum < "$SHIP/$cfg-$t.bin" | cut -c1-16)  rebuild == shipped, refold == shipped, text fixpoint, mdlint clean"
    n=$((n+1))
  done
done
echo "$n reference binaries reproduced"
