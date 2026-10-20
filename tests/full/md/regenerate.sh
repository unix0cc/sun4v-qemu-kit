#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Rewrite expected/blobs.sha256 from the current md/ tree. Review the diff before committing it.
#
# The pinned hashes are trust-on-first-use: they record whatever the tree builds today. So this refuses to record a tree that
# fails the checks that do NOT depend on a recorded value: roundtrip (deterministic, unfold/refold/mdlint hashes equal) and graph
# (no dangling arc, one root, every fwd/back paired, all reachable). A new md/<target>/ is picked up by wildcard; run this once
# after adding it.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export OUTDIR=${OUTDIR:-$(mktemp -d "${TMPDIR:-/tmp}/md-test.XXXXXX")}
for t in roundtrip graph; do
  "$HERE/internal/$t.sh" > "$OUTDIR/regen-$t.log" 2>&1 || { echo "regenerate: refusing to pin -- $t fails:" >&2; cat "$OUTDIR/regen-$t.log" >&2; exit 1; }
done
. "$HERE/lib/env.sh"
build_ours
mkdir -p "$HERE/expected"; : > "$HERE/expected/blobs.sha256"
for c in $CONFIGS; do for t in md hv; do
  echo "$(sha256sum < "$OUT/$c/1up-$t.bin" | cut -d' ' -f1)  $c/1up-$t.bin" >> "$HERE/expected/blobs.sha256"; done; done
cat "$HERE/expected/blobs.sha256"
