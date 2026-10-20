#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# forth64.sh -- thin wrapper standing in for Sun's ${FORTH}/${FORTH64}/${COMPILER64}.
# Runs the cross-built 64-bit engine under qemu-sparc64 linux-user.
#
# Every OBP make rule that calls "${FORTH} <args>" or "${FORTH64} <args>" gets
# this instead, unchanged otherwise -- the recipes in Sun's arch/common.mk,
# forth.mk and every per-dropin depend.mk are reused verbatim (the whole
# substitution inventory is TESTS section 6); only the tool path changes.
#
# Requires BP set in the environment (not just -D'd -- the engine's own
# expand_name() reads getenv("BP"), confirmed by building).
set -eu
: "${QEMU_SPARC64:?set to the qemu-sparc64 linux-user binary}"
: "${FORTH64_BIN:?set to the cross-built forth64 binary}"
exec "$QEMU_SPARC64" "$FORTH64_BIN" "$@"
