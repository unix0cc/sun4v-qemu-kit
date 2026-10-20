#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# src-pristine.sh -- every file under src/hypervisor and src/obp that
# PRISTINE-MANIFEST records really is byte-for-byte what Sun shipped in
# OpenSPARCT2_Arch.1.2.tar.bz2 -- not just "what the manifest says", which
# src-intact.sh already checks against the working tree alone. This is the
# other half of provenance: it does not trust the manifest's own hashes, it
# re-derives them from the tarball.
#
# One tar pass reading the whole (bzip2) archive once, regardless of how
# many of its 27,000+ members are needed -- bzip2 has no random access, so
# asking for fewer members would not make this faster. Expect a minute or
# two.
#
# Usage: src-pristine.sh <OpenSPARCT2_Arch.1.2.tar.bz2>
#        (or set OPENSPARC_T2 to the path and omit the argument)
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)            # tests/full/obp/external
REPO=$(cd "$HERE/../../../.." && pwd)
TARBALL=${1:-${OPENSPARC_T2:-}}
[ -n "$TARBALL" ] || { echo "usage: $0 <OpenSPARCT2_Arch.1.2.tar.bz2>  (or set OPENSPARC_T2)" >&2; exit 2; }
[ -f "$TARBALL" ] || { echo "FAIL: $TARBALL not found" >&2; exit 1; }
M=$REPO/PRISTINE-MANIFEST

W=$(mktemp -d "${TMPDIR:-/tmp}/src-pristine.XXXXXX")
trap 'rm -rf "$W"' EXIT

echo "=== src-pristine: extracting the needed members from $(basename "$TARBALL") ==="
# path (repo-relative) -> tar member: strip the leading "src/", prepend "./".
# Only src/hypervisor and src/obp came from this tarball.
awk '!/^#/ && ($4 ~ /^src\/hypervisor\// || $4 ~ /^src\/obp\//) {
        m = $4; sub(/^src\//, "./", m); print m
    }' "$M" > "$W/members.txt"
n_members=$(wc -l < "$W/members.txt")
tar xjf "$TARBALL" -C "$W" -T "$W/members.txt" \
    || { echo "FAIL: tar extraction (see above)" >&2; exit 1; }

echo "=== src-pristine: comparing $n_members extracted files against $M ==="
bad=0; n=0
while read -r mtime size sha path; do
    case "$mtime" in \#*|"") continue ;; esac
    case "$path" in src/hypervisor/*|src/obp/*) ;; *) continue ;; esac
    n=$((n + 1))
    member="./${path#src/}"
    extracted="$W/$member"
    if [ ! -f "$extracted" ]; then
        echo "  NOT IN TARBALL: $path ($member)"; bad=1; continue
    fi
    actual=$(sha256sum "$extracted" | cut -d' ' -f1)
    if [ "$actual" != "$sha" ]; then
        echo "  HASH MISMATCH $path: manifest says $sha, tarball has $actual"; bad=1
    fi
done < "$M"

[ "$n" -gt 0 ] || { echo "FAIL: no src/hypervisor or src/obp lines in $M" >&2; exit 1; }
if [ "$bad" != 0 ]; then
    echo "FAIL: src-pristine -- $M disagrees with $(basename "$TARBALL") (see above)"
    exit 1
fi
echo "PASS: src-pristine -- $n files match $(basename "$TARBALL") exactly" \
     "(sha256 of the tarball: $(sha256sum "$TARBALL" | cut -d' ' -f1))"
