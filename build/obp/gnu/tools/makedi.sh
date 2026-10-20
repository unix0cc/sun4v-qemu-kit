#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# makedi.sh -- stands in for Sun's ${MAKEDI} = ${TOOLS}/makedi -c.
#
# makedi writes the on-disk OBMD header (magic/size/checksum) as raw C
# int/short fields with no explicit byte-order handling anywhere in
# sys/dropins.h -- correct by construction only on a big-endian host, which
# every host that has ever built this before was. Cross-built
# for sparc64-linux-gnu and run under qemu-sparc64 here specifically because
# that makes the untouched, unguarded native-int writes correct again
# without patching Sun's header.
set -eu
: "${QEMU_SPARC64:?}"
: "${MAKEDI_SPARC_BIN:?set to the cross-built, byte-order-safe makedi}"
exec "$QEMU_SPARC64" "$MAKEDI_SPARC_BIN" -c "$@"
