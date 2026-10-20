#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Our own configs. For every md/<target>/ and each of its two blobs, measure the hash at every stage:
#
#   B0  the blob as built (sha256 H0)
#   S1  unfold(B0)          -> mdgen -> B1   H1 must equal H0
#   mdlint(B1)              must be clean (silent, exit 0)
#   S2  unfold(B1)          must equal S1 (text fixpoint)
#   S2                      -> mdgen -> B2   H2 must equal H0
#   mdlint -t (B0) and (B2) must print identical text
#   a second, independent `make md` gives H0 again (the build is deterministic)
. "$(dirname "$0")/../lib/env.sh"
build_ours
fail() { echo "FAIL: $*" >&2; exit 1; }
n=0
for c in $CONFIGS; do
  for t in md hv; do
    b0=$OUT/$c/1up-$t.bin; w=$OUT/rt-$c-$t
    h0=$(sha256sum < "$b0" | cut -d' ' -f1)
    python3 "$UNFOLD" "$b0" > "$w.s1"
    "$MDGEN" --binary --outfile "$w.b1" "$w.s1"
    h1=$(sha256sum < "$w.b1" | cut -d' ' -f1); [ "$h1" = "$h0" ] || fail "$c-$t: refold B1 hash $h1 != $h0"
    "$MDLINT" "$w.b1" > "$w.lint" 2>&1 || fail "$c-$t: mdlint rejects B1: $(head -1 "$w.lint")"
    [ ! -s "$w.lint" ] || fail "$c-$t: mdlint is not silent: $(head -1 "$w.lint")"
    python3 "$UNFOLD" "$w.b1" > "$w.s2"; cmp -s "$w.s1" "$w.s2" || fail "$c-$t: unfolded text is not a fixpoint"
    "$MDGEN" --binary --outfile "$w.b2" "$w.s2"
    h2=$(sha256sum < "$w.b2" | cut -d' ' -f1); [ "$h2" = "$h0" ] || fail "$c-$t: second refold B2 hash $h2 != $h0"
    cmp -s <("$MDLINT" -t "$b0") <("$MDLINT" -t "$w.b2") || fail "$c-$t: mdlint -t text differs between B0 and B2"
    make -s -C "$REPO" md TARGET="$c" OUTDIR="$OUT/again-$c" WORKDIR="$OUT/work-again-$c" >/dev/null
    cmp -s "$OUT/again-$c/1up-$t.bin" "$b0" || fail "$c-$t: second build differs (not deterministic)"
    echo "ok  $c-$t  H0=H1=H2=$(echo $h0 | cut -c1-16)  $(wc -c < "$b0") bytes, mdlint clean"
    n=$((n+1))
  done
done
echo "$n blobs: three hashes equal at every stage"
