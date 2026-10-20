#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
#
# As cc-nobuiltin.sh, and -xdepend=no too: Sun Studio 12.2 (cc 5.11) writes the _memcpy/_memset calls
# from its loop dependence analysis, which -xbuiltin=%none does not reach. (Measured on decomp.c at
# -fast: [-xbuiltin=%none] 2 calls, [-xbuiltin=%none -xdepend=no] 0.) Both go last, after -fast.
exec "$SUN_STUDIO/bin/cc" "$@" -xbuiltin=%none -xdepend=no
