#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# set-ok.sh <OUTDIR> <TARGET> [<SIGNATURE> | --stamp]
#
# One OUTDIR holds ONE firmware set. The files of two machines in it (q.bin and openboot.bin of legion, the MDs of pci) pass
# for a complete set: `make install` would take them. The first field of OUTDIR/.md-signature (written by the build,
# build/md.mk) says which machine the set is for. Silent and exit 0 when OUTDIR is new, empty, or holds the same machine;
# otherwise prints why on stdout and exits 1 (the Makefile turns that into an error at parse time).
#
#   with two arguments:   only the machine (TARGET) is compared: `make md MD_MEM=...` on a built set is fine, q.bin and openboot.bin
#                         do not depend on MD_MEM
#   with a SIGNATURE:     the whole signature (TARGET|...|MD_MEM|banner) is compared; `make install` names the set after TARGET and
#                         tells QEMU -m MD_MEM
#   with --stamp:         as with two arguments, and a set without .md-signature gets one that names TARGET (hv_reset and obp
#                         write the first files of a set; without it a later `make md TARGET=other` would find nothing to compare)
# Bourne sh (Solaris 10): no $( ), no ${x#y}, no test -e.
out=$1; target=$2; sig=$3; stamp=
if [ "$sig" = --stamp ]; then stamp=yes; sig=; fi
f=$out/.md-signature
have() { [ -f "$1" ] || [ -d "$1" ] || [ -h "$1" ]; }
if [ ! -f "$f" ]; then
    if [ -n "$stamp" ]; then mkdir -p "$out" && printf '%s|\n' "$target" > "$f"; fi
    exit 0
fi
old=`cat "$f"`
oldt=`printf '%s\n' "$old" | sed 's/|.*//'`
fw=
for m in reset.bin q.bin openboot.bin 1up-md.bin 1up-hv.bin; do
    if have "$out/$m"; then fw="$fw $m"; fi
done
[ -n "$fw" ] || exit 0
fwlist=`printf '%s\n' "$fw" | sed 's/^ //'`
if [ "$oldt" != "$target" ]; then
    echo "OUTDIR=$out holds a set for TARGET=$oldt ($fwlist); building TARGET=$target into it would mix two machines in one -L directory. Run make clean first, or use another OUTDIR"
    exit 1
fi
if [ -n "$sig" ] && [ "$old" != "$sig" ]; then
    echo "OUTDIR=$out was built as '$old'; TARGET and MD_MEM now say '$sig'. Build it again (make all), or give the same TARGET and MD_MEM"
    exit 1
fi
exit 0
