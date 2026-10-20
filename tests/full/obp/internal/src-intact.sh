#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# src-intact.sh -- every file PRISTINE-MANIFEST records is still that exact
# file: sha256 matches, nothing missing. Does not check mtime (git never
# preserves it; that is what scripts/restore-mtimes.sh is for, and it is
# cosmetic, not content).
#
# This is the internal half of src provenance: it proves the working tree
# matches what THIS repository claims was imported. It cannot prove the
# claim itself is honest -- that the manifest's hashes really are Sun's
# original files -- which needs the tarball (external/src-pristine.sh).
#
# No QEMU, no build: one sha256sum -c pass over ~1400 files.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)   # repo root
cd "$HERE"
M=PRISTINE-MANIFEST
[ -f "$M" ] || { echo "FAIL: $M not found" >&2; exit 1; }

n=$(grep -vc '^#' "$M")
[ "$n" -gt 0 ] || { echo "FAIL: $M has no data lines" >&2; exit 1; }

# ... and nothing else lies under src/: a file added there would be built into the firmware without being noticed
extra=$(LC_ALL=C comm -13 <(awk '!/^#/ {print $4}' "$M" | LC_ALL=C sort) <(find src -type f | LC_ALL=C sort))
if [ -n "$extra" ]; then
    echo "FAIL: src-intact -- files under src/ that $M does not list:" >&2; echo "$extra" | sed 's/^/    /' >&2; exit 1
fi

ERR=$(mktemp "${TMPDIR:-/tmp}/src-intact.XXXXXX"); trap 'rm -f "$ERR"' EXIT
if awk '!/^#/ {print $3 "  " $4}' "$M" | sha256sum -c --quiet - 2> "$ERR"; then
    echo "PASS: src-intact -- $n files match $M (sha256)"
else
    cat "$ERR" >&2 2>/dev/null
    echo "FAIL: src-intact -- $M and the working tree disagree (see above)" >&2
    exit 1
fi
