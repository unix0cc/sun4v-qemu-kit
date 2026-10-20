#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Regenerate offsets.h (and offsets.chk) without Sun's `stabs`, and check them against a real
# Sun-toolchain reference where one exists. Method: ../README.dwarf.
#
# Two differences
# from the original:
#
#   - T2/T1/ABI point at this repo's own vendored src/hypervisor and
#     abi/ next to this script, not the deduped reference tree. T1 include paths dropped
#     entirely -- confirmed unneeded.
#   - The original validates only against huron/legion, the one variant Sun
#     shipped a prebuilt offsets.h for -- no help for ontario/legion, our
#     actual target. This repo has something better for that: a real
#     Sun-toolchain-generated offsets.h for ontario/legion, WITH the same
#     QEMU_EXTRA_OPTIONS this script itself applies (built 2026-08-22, the
#     run that booted to the OBP prompt).
#     REFERENCE defaults to that file when PLATFORM/VARIANT match it.
#
# Usage: ./build-offsets.sh [workdir]
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
WORK=${1:-${OUTDIR:-$HOME/build/sun4v-qemu-kit/gnu}/offsets-work}

T2=$REPO/src/hypervisor/src
ABI=$HERE/abi

PLATFORM=${PLATFORM:-ontario}
VARIANT=${VARIANT:-legion}
OFFSETS_IN=$T2/greatlakes/$PLATFORM/src/offsets.in

if [ "$PLATFORM/$VARIANT" = "ontario/legion" ]; then
    REFERENCE=${REFERENCE:-$HERE/reference/offsets.ontario-legion.h}
else
    REFERENCE=${REFERENCE:-$T2/greatlakes/$PLATFORM/$VARIANT/offsets.h}
fi

mkdir -p "$WORK"
cd "$WORK"

# The -D set comes straight out of the Makefiles (hv-opts.sh), with
# QEMU_EXTRA_OPTIONS (build/hv_reset/options.mk) appended last via HV_EXTRA_OPTS so it
# overrides. __sparcv9 is implied by Sun's -xarch=v9a; the Linux
# cross-compiler spells it __sparc_v9__/__arch64__.
OPTS="-m64 $GNU_CSTD -D__sparcv9 $("$HERE/hv-opts.sh" "$PLATFORM" "$VARIANT")"

INC="-I$PWD/override \
 -I$T2/greatlakes/$PLATFORM/include \
 -I$T2/greatlakes/common/include \
 -I$T2/common/include \
 -I$T2/include \
 -I$ABI \
 -I."

# Step 1: shadow copies of the few headers whose forward-use declarations ISO C
# rejects.  Probe = offsets.in's own include list, nothing more.
grep '^#' "$OFFSETS_IN" > probe.c
echo 'int __probe;' >> probe.c
python3 "$HERE/mkoverrides.py" --override "$PWD/override" --probe probe.c -- $OPTS $INC

# Step 2: the offsets themselves, with the pipeline shared with the Sun path
# (../offsets-dwarf.sh, README.dwarf): gcc writes DWARF for a stub that refers to every
# type offsets.in names, ../dwarf2genassym.pl reads the layout back with the semantics of
# Sun's `stabs` -- including "a struct with no member list yields all its members" -- so
# nothing needs supplementing. gcc wants -gdwarf-4: its data member locations are then
# plain constants.
GCC=${GCC:-sparc64-linux-gnu-gcc}
READELF=${READELF:-sparc64-linux-gnu-readelf}
rm -f offsets-n1.dump
for t in offsets.h offsets.chk; do
    sh "$HERE/../offsets-dwarf.sh" -t $t -i "$OFFSETS_IN" -c "$GCC $OPTS $INC" \
        -g -gdwarf-4 -d "$READELF --debug-dump=info" -f readelf
done

# The flags, for tests/full/hv_reset/internal/offsets-cross-check.sh, which computes the same
# values a second, independent way (lib/genoffsets.py) and compares.
printf 'OPTS="%s"\nINC="%s"\n' "$OPTS" "$INC" > offsets.flags

# Step 3: validate against a real reference, if one exists for this pairing.
if [ -f "$REFERENCE" ]; then
    grep -E '^#define[[:space:]]+[A-Za-z_0-9]+[[:space:]]+0x' "$REFERENCE" \
        | awk '{print $2, $3}' | sort > sun.vals
    grep -E '^#define[[:space:]]+[A-Za-z_0-9]+[[:space:]]+0x' offsets.h \
        | awk '{print $2, $3}' | sort > mine.vals
    join sun.vals mine.vals -o 1.1,1.2,2.2 > both.vals
    bad=$(awk '$2 != $3' both.vals | wc -l)
    echo "validated $(wc -l < both.vals) numeric symbols against $REFERENCE, $bad mismatch(es)"
    [ "$bad" -eq 0 ] || { awk '$2 != $3' both.vals | head; exit 1; }
    # For ontario/legion the reference is made by Sun Studio 11 and `stabs` from this very
    # offsets.in, and the output is expected to be the same file, byte for byte.
    if [ "$PLATFORM/$VARIANT" = "ontario/legion" ]; then
        if cmp -s offsets.h "$REFERENCE"; then echo "offsets.h is byte-identical to the reference (nothing supplemented)"
        else echo "offsets.h differs from the reference outside the numeric symbols" >&2; diff offsets.h "$REFERENCE" | head -20 >&2; exit 1; fi
        REFERENCE_CHK="${REFERENCE%.h}.chk"
        if [ -f "$REFERENCE_CHK" ]; then
            if cmp -s offsets.chk "$REFERENCE_CHK"; then echo "offsets.chk is byte-identical to the reference"
            else echo "offsets.chk differs from the reference" >&2; diff offsets.chk "$REFERENCE_CHK" | head -20 >&2; exit 1; fi
        fi
    fi
else
    echo "no reference offsets.h for $PLATFORM/$VARIANT -- generated but unvalidated"
fi
