#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
#
# Sun cc with -xbuiltin=%none as its LAST option. Given to Sun's make as CC= when the cc rewrites
# copy and clear loops into calls to _memcpy/_memset (config.mk, SUN_CC_NOBUILTIN): hv_reset.mk and
# obp.mk, whose code (q.bin, and decomp.o in the PROM) is linked without a libc.
#
# Last, because OBP compiles decomp.c with `-fast`, and -fast implies -xbuiltin=%all: the flag
# only works after it. (Measured on Developer Studio 12.6: [-xbuiltin=%none -fast] still leaves
# _memset undefined, [-fast -xbuiltin=%none] does not.)
#
# SUN_STUDIO comes from the environment, which the sun path's make invocations set.
exec "$SUN_STUDIO/bin/cc" "$@" -xbuiltin=%none
