#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Print the -D/-U set for a platform/variant, straight out of the Makefiles.
#
# Preferred over mining a shipped binary's embedded compile lines: it works
# for variants Sun never shipped a binary of (ontario/legion, notably), and it
# is the actual source of truth rather than a build artefact. $(EXTRA_OPTIONS)
# and other make variables are dropped.
#
# Adjusted only for this
# repo's layout: T2 defaults to this repo's own pristine src/hypervisor.
#
# Lines conditionally prefixed `$(DESUPPORT_NIAGARA_1x)PLAT_OPTIONS += ...`
# (ontario/Makefile.platform's -DNIAGARA_ERRATUM_39/43) don't start with
# "PLAT_OPTIONS", so a plain `^PLAT_OPTIONS` match misses them -- the sed
# pattern strips an optional literal `$(DESUPPORT_NIAGARA_1x)` prefix too.
# DESUPPORT_NIAGARA_1x is commented out in every Makefile.platform this repo
# ships, i.e. always empty, so this matches what Sun's own make actually does
# with the file today. Confirmed 2026-09-14: without this, GNU-built q.bin's
# plat_halt_strand() had no erratum #39 version guard at all (unconditional
# halt, not "guarded, defaults to on") and the interrupt vector trap slot
# (tt0_060) was missing erratum #43's `membar #Sync` -- both silently, since
# nothing here ever compares sun and gnu output at the instruction level.
T2=${T2:-"$(cd "$(dirname "$0")/../../../src/hypervisor/src" && pwd)"}
PLATFORM=$1
VARIANT=$2
if [ -z "$PLATFORM" ] || [ -z "$VARIANT" ]; then
    echo "usage: hv-opts.sh <platform> <variant>" >&2; exit 2
fi
G=$T2/greatlakes

{
    sed -n 's/^\(\$(DESUPPORT_NIAGARA_1x)\)\?PLAT_OPTIONS *+*= *//p' "$G/$PLATFORM/Makefile.platform"
    sed -n 's/^OPTIONS *+*= *//p'      "$G/$PLATFORM/$VARIANT/Makefile"
} | tr ' \t' '\n\n' | grep -E '^-[DU]' | grep -v '\$' | awk '!seen[$0]++' | tr '\n' ' '

# $HV_EXTRA_OPTS is appended last, so it overrides. build/hv_reset/options.mk sets it
# from QEMU_EXTRA_OPTIONS -- see that file for what and why.
printf '%s\n' "$HV_EXTRA_OPTS"
