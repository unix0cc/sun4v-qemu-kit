#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Our blobs against the recorded hashes in expected/blobs.sha256. A failure here is not necessarily a
# bug -- it means a config's MD changed. Look at what changed (unfold both and diff), and if it is
# intended run tests/full/md/regenerate.sh and commit expected/ together with the md/ change.
. "$(dirname "$0")/../lib/env.sh"
build_ours
: > "$OUT/now.sha256"
for c in $CONFIGS; do for t in md hv; do
  echo "$(sha256sum < "$OUT/$c/1up-$t.bin" | cut -d' ' -f1)  $c/1up-$t.bin" >> "$OUT/now.sha256"; done; done
if diff -u "$HERE/expected/blobs.sha256" "$OUT/now.sha256"; then echo "ok  $(wc -l < "$OUT/now.sha256") blobs match expected/blobs.sha256"; else
  echo "FAIL: blobs differ from expected/blobs.sha256 (see diff above)" >&2; exit 1; fi
