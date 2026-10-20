#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# makeprom.sh -- stands in for Sun's ${MAKEPROM}.
#
# Cross-built for sparc64-linux-gnu (same byte-order reasoning as makedi.sh)
# AND carrying a real source patch (patches/obp/gnu/makeprom-ptr-roundup.patch):
# sys/dropins.h's ROUNDUP() macro casts through (unsigned int), correct only
# on the 32-bit ABI Sun's own tools were always built for -- on any 64-bit
# host (this one or plain x86_64) it truncates a real pointer to 32 bits at
# the two call sites in makeprom.c that round a pointer rather than a size.
# Root-caused via gdb-multiarch attached to qemu-sparc64's own gdbstub
# Without this patch makeprom segfaults inside is_dropin()'s
# strncmp on a corrupted pointer.
set -eu
: "${QEMU_SPARC64:?}"
: "${MAKEPROM_SPARC_BIN:?set to the cross-built, pointer-fixed makeprom}"
exec "$QEMU_SPARC64" "$MAKEPROM_SPARC_BIN" "$@"
