#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# compare-reference.sh -- per-artefact comparison of a GNU-path build tree
# against a captured Sun-toolchain build tree (TESTS, Appendix A).
#
# Usage: compare-reference.sh <our OBP_BLD> <reference release dir> [<our openboot.bin> [<reference openboot.bin>]]
#
# The "reference" side can be any other build tree, e.g. a second GNU build made
# with a different qemu-sparc64 (Phase 5.5): then pass that build's OUTDIR
# openboot.bin as the 4th argument, since a build tree has none of its own.
#
# Per file: IDENTICAL, or DIFFERENT with byte count / first offset / sizes.
# For openboot.bin additionally walks both OBMD chains record by record, so
# "differs only inside the bootprom record" is a measured statement, not a
# guess. Exit status is not a verdict (bootprom is expected to differ, see
# M2.4); read the table.
set -u
OURS=${1:?our build dir}; ORA=${2:?reference dir}; IMG=${3:-$OURS/openboot.bin}; OIMG=${4:-$ORA/openboot.bin}

row() {  # name ours reference
    if [ ! -f "$2" ]; then printf '%-10s %s (missing on our side)\n' MISSING "$1"; return; fi
    if [ ! -f "$3" ]; then printf '%-10s %s (missing on reference side)\n' NO-REFERENCE "$1"; return; fi
    if cmp -s "$2" "$3"; then printf '%-10s %s\n' IDENTICAL "$1"
    else
        n=$(cmp -l "$2" "$3" 2>/dev/null | wc -l | tr -d ' ')
        first=$(cmp "$2" "$3" 2>&1 | sed -n 's/.*differ: byte \([0-9]*\).*/\1/p')
        printf '%-10s %s  (%s bytes differ, first at %s; sizes %s / %s)\n' DIFFERENT "$1" \
            "$n" "${first:-EOF}" "$(stat -c %s "$2")" "$(stat -c %s "$3")"
    fi
}

echo "== reset chain (the Phase 5.3 question) =="
for f in decomp.o version.fth revlevel stand.dic headers acfheaders reset.o reset.symbols reset.bin; do
    row "$f" "$OURS/$f" "$ORA/$f"
done
echo
echo "== bootprom (expected to differ: M2.4, host-address class) =="
for f in bootprom.bin bootprom.di; do row "$f" "$OURS/$f" "$ORA/$f"; done
echo
echo "== every other dropin =="
for f in "$OURS"/*.di; do
    b=$(basename "$f")
    case $b in bootprom.di|builtin.di) continue;; esac
    row "$b" "$f" "$ORA/$b"
done | sort | uniq -c -w9
echo
echo "== images =="
row builtin.di "$OURS/builtin.di" "$ORA/builtin.di"
row openboot.bin "$IMG" "$OIMG"
echo
echo "== openboot.bin, record by record =="
python3 - "$IMG" "$OIMG" <<'EOF'
import struct, sys
def chain(b):
    off, out = 0, []
    while off + 32 <= len(b) and b[off:off+4] == b"OBMD":
        size = struct.unpack(">I", b[off+4:off+8])[0]
        name = b[off+16:off+32].split(b"\0")[0].decode(errors="replace")
        out.append((off, size, name)); off += 32 + ((size + 3) & ~3)
    return out, off
A = open(sys.argv[1], "rb").read(); B = open(sys.argv[2], "rb").read()
ca, ea = chain(A); cb, eb = chain(B)
print(f"{'record':<18}{'ours@':>8} {'size':>7}   {'reference@':>8} {'size':>7}   verdict")
for (oa, sa, na), (ob, sb, nb) in zip(ca, cb):
    ra = A[oa:oa+32+((sa+3)&~3)]; rb = B[ob:ob+32+((sb+3)&~3)]
    if na != nb: v = f"NAME MISMATCH ({nb})"
    elif ra == rb: v = "identical"
    else:
        n = sum(1 for x, y in zip(ra, rb) if x != y) + abs(len(ra) - len(rb))
        v = f"differs ({n} bytes)"
    print(f"{na:<18}{oa:>#8x} {sa:>7}   {ob:>#8x} {sb:>7}   {v}")
if len(ca) != len(cb): print(f"record count differs: ours {len(ca)}, reference {len(cb)}")
print(f"chain end: ours {ea} of {len(A)}, reference {eb} of {len(B)}")
EOF
