#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# decomp-size-sun.sh -- decomp-size for Sun's make, order-independent.
#
# Sun's arch/common.mk computes it as  size -f decomp.o | sed ... | nawk -f getsz.awk,
# and getsz.awk adds up the fields after "text" in pairs until it sees "data". That is
# .text + .bss + .data only when the object lists them in that order, as Sun Studio 11's
# does (text, bss, data). Developer Studio 12.6 lists text, data, bss: the awk stops
# before .bss and decomp-size comes out 8 short. decomp-size is not cosmetic: reset.o is
# assembled with it to find where the next dropin starts, so a short one makes the
# decompressor read its input from the wrong place ("Bad MAGIC number" -> store to
# address 1 -> the PROM never prints anything). Sum the three sections by name instead,
# the same sum build/obp/gnu/tools/decomp-size.sh makes. Same value as Sun's for Sun
# Studio 11; build/obp/pad-reset-bin.sh then pads the file out to it (.bss has no bytes).
#
# The sections are not packed in the image: ld aligns decomp's .text and .data (Developer Studio
# 12.6: 16 and 8) after reset.o's 4-aligned text, and elf2bin keeps those gaps (patches/obp/sun/
# elf2bin-keep-section-gap.patch). Declared shorter than the image, decomp-size makes pad-reset-bin.sh
# refuse the file; declared longer, the surplus is zeros at the end. So add what alignment beyond 4
# can cost: (text align - 4) + (data align - 4). Sun Studio 11's objects are 4-aligned: nothing added,
# its decomp-size stays what Sun's pipeline gave.
#
# Bourne sh and old awk (nawk for the part that needs sub()): it runs on the Solaris guest.
OBJ=$1
[ -f "$OBJ" ] || { echo "decomp-size-sun.sh: no such file: $OBJ" >&2; exit 1; }
SUM=`/usr/ccs/bin/size -f "$OBJ" | sed -e 's/+/ /g' -e 's/(\./ /g' -e 's/)//g' |
    awk '{ for (i = 2; i <= NF; i++)
               if ($i == "text" || $i == "data" || $i == "bss") s += $(i - 1)
           print s }'`
# sh_addralign of .text and .data, in hex as elfdump prints it
AL=`/usr/ccs/bin/elfdump -c "$OBJ" | /usr/bin/nawk '
    /sh_name:/ { n = $0; sub(/.*sh_name: */, "", n); sub(/[ \t].*/, "", n); cur = n }
    /sh_addralign:/ { a = $0; sub(/.*sh_addralign: *0x/, "", a); sub(/[^0-9a-f].*/, "", a); al[cur] = a }
    END { print al[".text"], al[".data"] }'`
SLACK=0
for a in $AL
do
    case $a in
    10) SLACK=`expr $SLACK + 12` ;;
    8)  SLACK=`expr $SLACK + 4` ;;
    20) SLACK=`expr $SLACK + 28` ;;
    esac
done
expr $SUM + $SLACK
