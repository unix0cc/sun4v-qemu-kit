#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Build mdgen/mdlint with GNU tools.
#   usage: build.sh <srcdir> <outdir> <patch>
#
# <srcdir>  src/hypervisor/src
# <outdir>  scratch dir; sources are copied to <outdir>/work and built there
# <patch>   patches/mdtools/gnu/mdgen-mdlint-host-endian.patch
#
# src/ is never modified: the sources are copied out and the patch is applied
# to the copy. The patch gives the network-byte-order macros a little-endian
# arm (Sun's #else is just `#error`) and adds one hton64() Sun forgot. Its
# header says why. mdlex.c is regenerated with flex so the lexer comes from
# source, and -include stdint.h is passed because md_impl.h relies on Solaris
# header pull-in order (a flag, not a source change).
#
# Output validated byte-for-byte against a known-good mdgen -- see the README.

set -e
SRC=$1
OUT=$2
PATCHFILE=$3
if [ -z "$SRC" ] || [ -z "$OUT" ] || [ -z "$PATCHFILE" ]; then
    echo "usage: build.sh <srcdir> <outdir> <patch>" >&2; exit 2
fi

CC=${CC:-gcc}
FLEX=${FLEX:-flex}
PATCH=${PATCH:-patch}
WORK="$OUT/work"

rm -rf "$WORK"
mkdir -p "$WORK"
cp -Rp "$SRC/support/mdgen" "$SRC/support/mdlint" "$SRC/include" "$SRC/common" "$WORK/"

"$PATCH" -p1 -d "$WORK" -i "$PATCHFILE" </dev/null
# Second, cosmetic patch from the same directory: uint64_t printf formats
# (see its header). Kept separate because it changes no output.
"$PATCH" -p1 -d "$WORK" -i "$(dirname "$PATCHFILE")/mdgen-mdlint-printf-int64.patch" </dev/null

# Sun ships a generated mdlex.c; regenerate it so the lexer comes from source.
"$FLEX" -Pmdlex -o "$WORK/mdgen/mdlex.c" "$WORK/mdgen/mdlex.l"

# -Werror on the classes GCC 14 rejects by default and on -Wformat: both
# patches leave these clean (the byte-order one added the hton64 Sun forgot,
# the printf one the PRIx64s), and a regression must fail the build, not
# scroll past. Sun's real bug here -- the missing hton64 -- is exactly the
# kind that only shows on a build where a new warning stands out.
STRICT="-Werror=implicit-function-declaration -Werror=implicit-int -Werror=format"
CFLAGS="-O2 -I$WORK/include -I$WORK/common/include -Wno-unknown-pragmas -include stdint.h -include string.h $STRICT"

cd "$WORK"
$CC $CFLAGS -o "$OUT/mdgen" \
    mdgen/mdmain.c mdgen/mdparse.c mdgen/output_bin.c mdgen/output_text.c \
    mdgen/output_dot.c mdgen/allocate.c mdgen/warning.c mdgen/fatal.c \
    mdgen/vfatal.c mdgen/mdlex.c
$CC $CFLAGS -Imdlint -o "$OUT/mdlint" \
    mdlint/mdlint.c mdlint/allocate.c mdlint/warning.c mdlint/fatal.c mdlint/vfatal.c

echo "mdgen, mdlint -> $OUT/"
