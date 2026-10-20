#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
#
# offsets.h and offsets.chk from DWARF -- the one piece of the hypervisor build that
# both toolchains share. Called by the gnu path (gnu/build-offsets.sh) and, through
# patches/hv/hv-ds12-offsets-dwarf.patch, by Sun's make when the cc writes no stabs.
# Background and the reasons: README.dwarf in this directory.
#
#   sh offsets-dwarf.sh -t offsets.h|offsets.chk -i offsets.in -c "CC FLAGS" -d "DUMP" [-g GFLAG] [-f FMT] [-m MODEL]
#
#   -t  what to make: offsets.h (stabs -t genassym) or offsets.chk (stabs -t asmcheck)
#   -i  offsets.in
#   -c  the compile line, cc plus its flags and -D/-I set (the compiler's own preprocessor
#       and compiler are both run with it). Word-split, not shell-parsed: flags with
#       quoting would not survive. The current sets have none.
#   -d  the command that dumps an object file's DWARF as text:
#         Developer Studio 12.6   /opt/developerstudio12.6/bin/dwarfdump        (-f dwarfdump)
#         gcc                     sparc64-linux-gnu-readelf --debug-dump=info   (-f readelf)
#   -g  the cc's flag for debug info (default -g; gcc wants -gdwarf-4: plain constants
#       for member offsets)
#   -f  format of that dump for dwarf2genassym.pl (default: it detects)
#   -m  data model (default lp64)
#
# Runs in the current directory and leaves offsets-n1.dump there: both targets need the
# same DWARF, so it is made once and reused. Remove it to force a new one.
#
# Written for Solaris' Bourne /bin/sh (the Sun path runs it there): no $( ), no ${x%%y}.

set -e

HERE=`dirname "$0"`
GEN="$HERE/dwarf2genassym.pl"

TARGET= IN= CCLINE= DUMP= GFLAG=-g FMT=auto MODEL=lp64
while getopts t:i:c:d:g:f:m: opt
do
    case $opt in
    t) TARGET=$OPTARG ;;
    i) IN=$OPTARG ;;
    c) CCLINE=$OPTARG ;;
    d) DUMP=$OPTARG ;;
    g) GFLAG=$OPTARG ;;
    f) FMT=$OPTARG ;;
    m) MODEL=$OPTARG ;;
    *) echo "usage: offsets-dwarf.sh -t offsets.h|offsets.chk -i offsets.in -c \"CC FLAGS\" -d \"DUMP\" [-g GFLAG] [-f FMT] [-m MODEL]" >&2; exit 2 ;;
    esac
done

case "$TARGET" in
offsets.h)   TYPE=genassym ;;
offsets.chk) TYPE=asmcheck ;;
*) echo "offsets-dwarf.sh: -t must be offsets.h or offsets.chk, got '$TARGET'" >&2; exit 2 ;;
esac
[ -f "$IN" ]      || { echo "offsets-dwarf.sh: no offsets.in ($IN)" >&2; exit 2; }
[ -n "$CCLINE" ]  || { echo "offsets-dwarf.sh: -c missing" >&2; exit 2; }
[ -n "$DUMP" ]    || { echo "offsets-dwarf.sh: -d missing" >&2; exit 2; }

# rc 1 from dwarf2genassym.pl means warnings only: a name offsets.in lists that no
# included header defines (snet_info; Sun's stabs says "Can't find snet_info" too).
# Anything above that is a failure.
run() {
    out=$1
    shift
    rc=0
    perl "$GEN" "$@" > "$out" 2> offsets-dwarf.err || rc=$?
    cat offsets-dwarf.err >&2
    rm -f offsets-dwarf.err
    [ $rc -le 1 ] || { echo "offsets-dwarf.sh: dwarf2genassym.pl $1 failed ($rc)" >&2; exit 1; }
}

if [ ! -s offsets-n1.dump ]; then
    # What Sun's rules start with: the #include lines of offsets.in as a C file. DWARF
    # carries a struct only when something refers to it, so the stub adds one variable
    # per type offsets.in names; which spelling (struct, union, enum, typedef) each
    # takes is read off the preprocessed text.
    grep '^#' "$IN" > offsets-n1.c
    $CCLINE -E offsets-n1.c > offsets-n1.i
    run offsets-n1.stub stub "$IN" offsets-n1.i
    cat offsets-n1.stub >> offsets-n1.c
    $CCLINE $GFLAG -c -o offsets-n1.o offsets-n1.c
    $DUMP offsets-n1.o > offsets-n1.dump
    rm -f offsets-n1.c offsets-n1.i offsets-n1.stub offsets-n1.o
fi

grep -v '^#' "$IN" > offsets.tmp
run "$TARGET" gen -f "$FMT" -m "$MODEL" -t $TYPE offsets.tmp offsets-n1.dump
rm -f offsets.tmp
[ -s "$TARGET" ] || { echo "offsets-dwarf.sh: empty $TARGET" >&2; exit 1; }
