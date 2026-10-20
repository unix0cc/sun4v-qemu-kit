#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Walk openboot.bin's OBMD dropin chain and fail unless it ends exactly at EOF.
#
# Worth doing on every build because the failure is completely silent. A chain
# that breaks at record N leaves every later dropin unreachable, and the PROM
# stops before printing a single character. No error message, no partial
# banner, nothing to grep for -- just a QEMU that sits there. Diagnosing that
# from the console costs an afternoon; walking the chain costs a millisecond.
#
# Each record: 32-byte header, then ROUNDUP(size,4) bytes of payload.
#
#     off 0   char magic[4]    "OBMD"
#     off 4   int  size        payload length
#     off 8   short res0
#     off 10  ushort chksum
#     off 12  int  res1
#     off 16  char name[16]
#
# (include/sys/dropins.h, struct OBMD)

set -e
IMG=$1
[ -n "$IMG" ] || { echo "usage: verify-dropin-chain.sh <path to openboot.bin>" >&2; exit 2; }
[ -f "$IMG" ] || { echo "verify-dropin-chain: no such file: $IMG" >&2; exit 1; }

perl -e '
    my $f = shift;
    open(my $fh, "<", $f) or die "open $f: $!\n";
    binmode $fh; local $/; my $d = <$fh>; close $fh;

    my ($off, $n) = (0, 0);
    while ($off < length($d)) {
        if ($off + 32 > length($d)) {
            die sprintf("BROKEN: record %d header at %#x runs past EOF (%d)\n", $n, $off, length($d));
        }
        my ($magic, $size) = unpack("a4N", substr($d, $off, 8));
        if ($magic ne "OBMD") {
            die sprintf("BROKEN at %#x: expected OBMD, got %s -- the declared length of the preceding record is wrong\n",
                        $off, unpack("H8", $magic));
        }
        my $name = unpack("Z16", substr($d, $off + 16, 16));
        printf "  %#08x  size=%-9d %s\n", $off, $size, $name;
        $off += 32 + (($size + 3) & ~3);
        $n++;
    }
    $off == length($d)
        or die sprintf("BROKEN: chain ends at %#x but file is %d bytes\n", $off, length($d));
    printf "verify-dropin-chain: OK -- %d dropins, ends exactly at EOF (%d bytes)\n", $n, length($d);
' "$IMG"
