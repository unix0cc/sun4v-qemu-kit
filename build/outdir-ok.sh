#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# outdir-ok.sh <OUTDIR> <SOURCE_ROOT>
#
# `make clean` removes OUTDIR wholesale, and so can build/toolchain-check.sh, so an OUTDIR that is, contains or holds
# the sources must never be accepted: `make all OUTDIR=$PWD` would delete the clone, and neither may a directory of
# someone's own files. Silent and exit 0 when OUTDIR is fine (a directory of our own output, an empty one, or one that
# does not exist yet). Otherwise prints why on stdout and exits 1; the
# Makefile turns that into an error at parse time. Bourne sh: it runs on Solaris too.
o=$1; src=$2; bad=
# Solaris 10's Bourne sh has no test -e.
have() { [ -f "$1" ] || [ -d "$1" ] || [ -h "$1" ]; }
if [ -z "$o" ]; then echo "OUTDIR is empty"; exit 1; fi
# The paths are used unquoted in many places: a space or a tab in one breaks the build without saying why.
case "$o" in
*" "*|*"	"*) echo "refusing OUTDIR=$o: it has a space or a tab in it. OUTDIR must be a path without one"; exit 1 ;;
esac
if [ -d "$o" ]; then
    real=`cd "$o" && pwd`; here=`cd "$src" && pwd`
    case "$here/" in "$real"/*) bad="is the source tree or contains it" ;; esac
    if [ "$real" = / ]; then bad="is /"; fi
    if [ "$real" = "$HOME" ]; then bad="is your home directory"; fi
    for m in Makefile config.mk .git; do
        if have "$real/$m"; then bad="holds sources or a build directory ($m)"; fi
    done
    # Anything else that is not empty must look like our own output: make clean would delete it all.
    if [ -z "$bad" ] && [ -n "`ls -a "$real" 2>/dev/null | sed -e '/^\.$/d' -e '/^\.\.$/d'`" ]; then
        ours=
        for m in .toolchain .md-signature _tmp reset.bin q.bin openboot.bin 1up-md.bin 1up-hv.bin nvram1; do
            if have "$real/$m"; then ours=yes; fi
        done
        if [ -z "$ours" ]; then bad="is not empty and does not look like build output"; fi
    fi
fi
if [ -n "$bad" ]; then
    echo "refusing OUTDIR=$o: it $bad. OUTDIR must be a directory of its own, such as ./output"
    exit 1
fi
exit 0
