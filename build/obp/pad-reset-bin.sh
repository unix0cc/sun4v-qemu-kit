#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Pad reset.bin's OBMD record to the length its own header claims.
#
# Works around a latent bug in Sun's OBP build chain, measured 2026-08-23.
# Without it the built openboot.bin is silently unbootable: the PROM dies
# before emitting a single character, with no diagnostic of any kind.
#
# WHAT GOES WRONG
#
# openboot.bin is a chain of OBMD dropin records. Each carries a 32-byte header
# declaring a payload `size`, and the next record starts at
#
#     off + 32 + ROUNDUP(size, 4)
#
# so the chain is a walk. One wrong length makes every later dropin
# unreachable.
#
# reset.bin is the first record. Its header size derives from
#
#     -s "d# ${DECOMPSIZE} constant decomp-size"        arch/common.mk:196
#
# where DECOMPSIZE comes from getsz.awk, which sums .text + .bss + .data. But
# .bss occupies no bytes in an ELF file, so elf2bin writes exactly .bss-many
# bytes fewer than the header promises. The first link lands short, `bootprom`
# is never found, and the PROM stops.
#
# Sun never hit this: their decomp.o had an empty .bss. Ours has 8 bytes --
# getcode_offset and getcode_oldcode, two uninitialised file-scope statics in
# tools/decomp.c that Sun C 5.8 places there. Any compiler that puts anything
# in .bss triggers it.
#
# THE REPAIR
#
# Append zeros to the declared length. Zeros are exactly right: the missing
# bytes ARE .bss. Computed from the header rather than hardcoded, so any
# compiler's .bss size works, and it is a no-op on a file that is already the
# right length.
#
# This needs no edit to Sun's source, which is why it lives here and not as a
# patch to src/obp.

set -e
RESET=$1
[ -n "$RESET" ] || { echo "usage: pad-reset-bin.sh <path to reset.bin>" >&2; exit 2; }
[ -f "$RESET" ] || { echo "pad-reset-bin: no such file: $RESET" >&2; exit 1; }

perl -e '
    my $f = shift;
    open(my $fh, "<", $f) or die "open $f: $!\n";
    binmode $fh; read($fh, my $hdr, 8) == 8 or die "$f: too short to hold an OBMD header\n";
    close $fh;
    my ($magic, $size) = unpack("a4N", $hdr);
    $magic eq "OBMD" or die "$f: not an OBMD record (magic=$magic)\n";

    my $need = 32 + (($size + 3) & ~3);
    my $have = -s $f;

    if ($have == $need) { printf "pad-reset-bin: %s already %d bytes, nothing to do\n", $f, $have; exit 0 }
    if ($have >  $need) { die sprintf("%s: %d bytes but header declares only %d -- unexpected, refusing\n", $f, $have, $need) }

    my $pad = $need - $have;
    open($fh, ">>", $f) or die "append $f: $!\n";
    binmode $fh; print $fh "\0" x $pad; close $fh;
    printf "pad-reset-bin: %s %d -> %d (+%d zero bytes; header declares payload %d)\n",
           $f, $have, $need, $pad, $size;
' "$RESET"
