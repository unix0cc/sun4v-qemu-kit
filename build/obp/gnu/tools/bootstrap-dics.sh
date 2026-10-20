#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# bootstrap-dics.sh <BP> -- build the kernel dictionaries from the one shipped
# root, os/sun/sparc/forth.dic, inside a scratch copy of src/obp/obp.
#
#   forth.dic -> kernel-xref.dic -> forth32-xref.dic -> k32t32-xref.dic
#             -> f32t32.dic -> k64t32.dic   (+ the .fth / .headless.fth listings)
#   f32t32.dic -> tokenize.dic               (the FCode tokenizer)
#
# The commands are Sun's own, as its release build runs them on Solaris
# (fm/kernel/sparc/depend.mk:112-200, os/sun/sparc/depend.mk,
# pkg/tokenizr/sparc/depend.mk), with two substitutions:
# ${FORTH} -> forth32.sh (the -m32 engine under qemu-sparc32plus) and
# `sort +1` -> `LC_ALL=C sort -k2` (TESTS section 6, row 15). The build then
# uses f32t32.dic and tokenize.dic exactly as Sun's does (forth.mk:73-79):
# FORTHTOOL for fonts/logo, TOKENIZE for every dropin.
#
# The six shipped dictionaries built here are deleted first, so nothing
# shipped can be mistaken for a result. Output is byte-identical to Sun's for
# every kernel and listing (TESTS, dic-kernels); the host dictionaries
# forth32-xref, f32t32 and tokenize differ only by the rdver shift and
# engine-binary addresses (TESTS, dic-host and 5.2).
#
# OBP_SEED selects where the chain starts:
#   forth.dic     (default) the first step above, from the shipped root
#   kernel-xref   skip it: start from kernel-xref.dic and its two listings, the files Sun shipped in fm/kernel/sparc
#                 (or those in OBP_SEED_DIR), so os/sun/sparc/forth.dic is never read. The fixpoint check
#                 below still runs and is what ties the seed to the sources.
#
# Env: QEMU_SPARC32, FORTH32_BIN (see forth32.sh). BP must be a copy, never
# a checkout -- these steps write into it. Optional: OBP_SEED, OBP_SEED_DIR (a directory with the three files; default: <repo>/src/obp/obp/fm/kernel/sparc).
set -euo pipefail
B=${1:?usage: bootstrap-dics.sh <BP = scratch copy of src/obp/obp>}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="$HERE/forth32.sh"
export BP="$B"
K=$B/fm/kernel/sparc; U=$B/os/sun/sparc; M=$B/fm/meta
OBP_SEED=${OBP_SEED:-forth.dic}
REPO="$(cd "$HERE/../../../.." && pwd)"
SEED_DIR=${OBP_SEED_DIR:-$REPO/src/obp/obp/fm/kernel/sparc}
case "$OBP_SEED" in
forth.dic)    [ -f "$U/forth.dic" ] || { echo "no root $U/forth.dic" >&2; exit 2; } ;;
kernel-xref)  for f in kernel-xref.dic kernel-xref.fth kernel-xref.headless.fth; do
                  [ -s "$SEED_DIR/$f" ] || { echo "bootstrap: no $f in the seed directory $SEED_DIR" >&2; exit 2; }
              done ;;
*)            echo "bootstrap: OBP_SEED must be forth.dic or kernel-xref, not '$OBP_SEED'" >&2; exit 2 ;;
esac
T=$B/pkg/tokenizr/sparc
rm -f $K/kernel-xref.dic $K/k32t32-xref.dic $K/k64t32.dic $U/forth32-xref.dic $U/f32t32.dic \
      $T/tokenize.dic

W=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-dics.XXXXXX")
trap 'rm -rf "$W"' EXIT
cd "$W"                         # nheads.*.dic and friends land here
heads() { # $1 = model name: the nheads/nheadless listings Sun sorts into $K
    "$F" -d nheads.$1.dic -s " nheads"    </dev/null | LC_ALL=C sort -k2 > $K/$1.fth
    "$F" -d nheads.$1.dic -s " nheadless" </dev/null | LC_ALL=C sort -k2 > $K/$1.headless.fth
}

if [ "$OBP_SEED" = kernel-xref ]; then
    echo "bootstrap: kernel-xref.dic (seed from $SEED_DIR)"
    cp "$SEED_DIR"/kernel-xref.dic $K/
    # the seed's listings are Sun's shipped files and begin with a 41-line copyright banner; the working copies are the listing only,
    # like the ones the first step writes (the fixpoint check below compares them with k32t32-xref's, which have no banner)
    for f in kernel-xref.fth kernel-xref.headless.fth; do tail -n +42 "$SEED_DIR/$f" > $K/$f; done
else
    echo "bootstrap: kernel-xref.dic"
    "$F" -d $U/forth.dic -F -D dic-file-name=$K/kernel-xref.dic -D KERNEL -D XREF \
        -x $K/kernel-xref.dic.idx -D nheads-dic-name=nheads.kernel-xref.dic \
        $M/conft32.fth $K/loadkern.fth </dev/null
    heads kernel-xref
fi

echo "bootstrap: forth32-xref.dic"
"$F" -d $K/kernel-xref.dic -u -D SUN4V -D dic-file-name=$U/forth32-xref.dic -D XREF \
    -x $U/forth32-xref.dic.xref -D kernel-hdr-file=$K/kernel-xref.fth \
    -s "" $U/loadutil.fth </dev/null

echo "bootstrap: k32t32-xref.dic"
"$F" -d $U/forth32-xref.dic -D dic-file-name=$K/k32t32-xref.dic -D KERNEL -D XREF -F \
    -x $K/k32t32-xref.dic.idx -D nheads-dic-name=nheads.k32t32-xref.dic \
    $M/conft32.fth $K/loadkern.fth </dev/null
heads k32t32-xref

# The chain metacompiles the 32-bit kernel twice: kernel-xref on the saved
# root, k32t32-xref on a host rebuilt around that new kernel. Equal means the
# first generation already reproduces itself (TESTS, dic-fixpoint) -- the
# fixpoint Sun's depend.mk:177-180 relies on when it offers the -xref models
# as replacements for forth.dic. Unequal means the root predates the kernel
# or metacompiler source; everything downstream would rest on a kernel built
# by an older host, so stop rather than build on it.
for f in dic fth headless.fth; do
    cmp -s $K/kernel-xref.$f $K/k32t32-xref.$f || {
        echo "bootstrap: kernel-xref.$f != k32t32-xref.$f -- the 32-bit kernel is not" >&2
        echo "  at a fixpoint from this root ($OBP_SEED; TESTS, dic-fixpoint)" >&2
        exit 1
    }
done
echo "bootstrap: kernel-xref == k32t32-xref (fixpoint)"

echo "bootstrap: f32t32.dic"
"$F" -d $K/k32t32-xref.dic -u -D SUN4V -D XREF -D dic-file-name=$U/f32t32.dic \
    -D kernel-hdr-file=$K/k32t32-xref.fth -s "" $U/loadutil.fth </dev/null

echo "bootstrap: k64t32.dic"
"$F" -d $U/f32t32.dic -D SUN4V -D dic-file-name=$K/k64t32.dic -D KERNEL \
    -D nheads-dic-name=nheads.k64t32.dic -s "" $M/conf64.fth $K/loadkern.fth </dev/null
heads k64t32

# loadtok.fth ignores dic-file-name and saves to this hardcoded path
# (loadtok.fth:57) -- one reason BP must be a copy.
echo "bootstrap: tokenize.dic"
"$F" -d $U/f32t32.dic -D SUN4V $T/loadtok.fth </dev/null

for f in $K/kernel-xref.dic $U/forth32-xref.dic $K/k32t32-xref.dic $U/f32t32.dic $K/k64t32.dic \
         $T/tokenize.dic; do
    [ -s "$f" ] || { echo "bootstrap: $f not written" >&2; exit 1; }
done
