#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Restore the original OpenSPARC file modification times into this working tree.
#
# git records content, not timestamps: a fresh clone gives every file the time
# it was checked out. PRISTINE-MANIFEST keeps Sun's original mtimes (and a
# sha256 of each file, so the same data verifies the import).
#
# Run from the repository root:
#   sh scripts/restore-mtimes.sh          restore mtimes
#   sh scripts/restore-mtimes.sh --verify check content against the manifest
set -eu

MANIFEST=PRISTINE-MANIFEST
[ -f "$MANIFEST" ] || { echo "no $MANIFEST here -- run from the repo root" >&2; exit 2; }

if [ "${1:-}" = "--verify" ]; then
    bad=0; n=0
    while read -r mtime size sha path; do
        case "$mtime" in \#*|"") continue ;; esac
        n=$((n + 1))
        if [ ! -f "$path" ]; then echo "MISSING  $path"; bad=$((bad + 1)); continue; fi
        got=$(sha256sum "$path" | cut -d' ' -f1)
        [ "$got" = "$sha" ] || { echo "CHANGED  $path"; bad=$((bad + 1)); }
    done < "$MANIFEST"
    echo "checked $n files, $bad differing from the pristine import"
    [ "$bad" -eq 0 ]
    exit
fi

n=0
while read -r mtime size sha path; do
    case "$mtime" in \#*|"") continue ;; esac
    [ -f "$path" ] || continue
    touch -d "$mtime" "$path"
    n=$((n + 1))
done < "$MANIFEST"
echo "restored mtimes on $n files"
