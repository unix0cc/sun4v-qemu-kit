#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# forth32.sh -- stands in for Sun's 32-bit ${FORTH} (os/unix/sparc/forth).
# Runs the -m32 cross-built engine under qemu-sparc32plus linux-user. Used
# only for the dictionary bootstrap (bootstrap-dics.sh); everything after it
# runs on the 64-bit engine (forth64.sh).
#
# Requires BP set in the environment, as forth64.sh does.
set -eu
: "${QEMU_SPARC32:?set to the qemu-sparc32plus linux-user binary}"
: "${FORTH32_BIN:?set to the cross-built forth32 binary}"
exec "$QEMU_SPARC32" "$FORTH32_BIN" "$@"
