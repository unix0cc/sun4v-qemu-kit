#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# decomp-ab.sh -- functional A/B of two decomp.o builds on every COMP dropin
# of a build tree. Usage:
#   decomp-ab.sh <build dir with *.di> <decomp.o A> <decomp.o B> [label-A] [label-B]
# For each .di: decompress the payload with both, compare A vs B, compare the
# produced length with the header's uncompressed size, and -- where the
# uncompressed original still exists in the build dir (X.fc for X.di,
# bootprom.bin) -- compare against it too. Exit 1 on any mismatch.
set -u
BLD=${1:?build dir}; A=${2:?decomp.o A}; B=${3:?decomp.o B}; LA=${4:-A}; LB=${5:-B}
HERE=$(cd "$(dirname "$0")" && pwd)
QEMU=${QEMU_SPARC32PLUS:-$HOME/build/qemu-linux-user/qemu-sparc32plus}
W=$(mktemp -d /tmp/decomp-ab.XXXXXX); trap 'rm -rf "$W"' EXIT

build() { # $1 decomp.o  $2 out   (grep's own status is meaningless here: 1 == "nothing to show")
    rm -f "$2"
    sparc64-linux-gnu-gcc -m32 -mcpu=v8 -O2 -ffreestanding -fno-builtin -fcommon \
        -nostdlib -static -Wl,-e,_start -Wl,-N "$HERE/harness.c" "$1" -o "$2" 2>&1 | grep -v "GNU-stack\|deprecated" || true
    [ -x "$2" ] || { echo "harness link failed for $1" >&2; exit 9; }
}
build "$A" "$W/ta"; build "$B" "$W/tb"
echo "harness $LA: $(sparc64-linux-gnu-readelf -h "$W/ta" | grep -E 'Machine|Flags' | tr -s ' ' | tr '\n' ' ')"
echo "harness $LB: $(sparc64-linux-gnu-readelf -h "$W/tb" | grep -E 'Machine|Flags' | tr -s ' ' | tr '\n' ' ')"

rc=0; n=0
printf '%-18s %8s %8s  %-9s %-9s %-10s %s\n' record comp uncomp "$LA=$LB" len==hdr vs-original original
for di in "$BLD"/*.di; do
    b=$(basename "$di" .di); [ "$b" = builtin ] && continue
    magic=$(dd if="$di" bs=1 skip=32 count=4 2>/dev/null | od -An -c | tr -d ' \n')
    [ "$magic" = COMP ] || { printf '%-18s %s\n' "$b" "(not COMP, skipped)"; continue; }
    tail -c +33 "$di" > "$W/p"
    csize=$(od -An -tu4 --endian=big -j36 -N4 "$di" | tr -d ' '); usize=$(od -An -tu4 --endian=big -j44 -N4 "$di" | tr -d ' ')
    "$QEMU" "$W/ta" < "$W/p" > "$W/oa"; ra=$?; "$QEMU" "$W/tb" < "$W/p" > "$W/ob"; rb=$?
    n=$((n+1))
    if [ $ra -ne 0 ] || [ $rb -ne 0 ]; then printf '%-18s %8s %8s  EXIT %s/%s\n' "$b" "$csize" "$usize" "$ra" "$rb"; rc=1; continue; fi
    if cmp -s "$W/oa" "$W/ob"; then ab=identical; else ab=DIFFERENT; rc=1; fi
    la=$(stat -c %s "$W/oa"); if [ "$la" -eq "$usize" ]; then lh=yes; else lh="NO($la)"; rc=1; fi
    orig=""; case $b in bootprom) o="$BLD/bootprom.bin";; font) o="$BLD/gallant-romfont.fnt";; sun-logo) o="$BLD/sun-logo.dat";; *) o="$BLD/$b.fc";; esac
    if [ -f "$o" ]; then if cmp -s "$W/oa" "$o"; then vo=identical; else vo=DIFFERENT; rc=1; fi; orig=$(basename "$o"); else vo="-"; orig="(gone)"; fi
    printf '%-18s %8s %8s  %-9s %-9s %-10s %s\n' "$b" "$csize" "$usize" "$ab" "$lh" "$vo" "$orig"
done
echo "records: $n; exit $rc"
exit $rc
