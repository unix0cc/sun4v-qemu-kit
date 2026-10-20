#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# The work directory: where the build keeps what is not the result (copies of the sources Sun's makefiles build in,
# mdgen and mdlint, probe files). OUTDIR holds only the firmware set.
#
#   workdir.sh path OUTDIR [WORKDIR]       print the work directory: WORKDIR if given, else
#                                          $TMPDIR (default /var/tmp)/sun4v-qemu-kit.<10 digits>, the digits being a checksum of
#                                          the user id and the absolute OUTDIR, so that one OUTDIR has one work directory
#   workdir.sh make WORKDIR SRC OUTDIR     create it and put the marker file in it; print why and exit 1 if it is not fit
#   workdir.sh clean WORKDIR SRC           remove it, but only a directory that carries the marker
#
# Why the marker: `make clean` must never remove a directory the build did not make. A WORKDIR given by hand that exists, is not
# empty and has no marker is refused by `make`, and left alone by `clean`.
# Why /var/tmp: on Solaris /tmp is memory and swap, and on Linux it may be either; /var/tmp is disk and persistent on both.
#
# Bourne sh (Solaris 10): no $( ), no ${x#y}, no test -e, no `!`.
MARK=.sun4v-qemu-kit-workdir

absolute() {
    case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "`pwd`" "$1" ;;
    esac
}
# One name for one directory, however it was written (a trailing slash, //, /./, .., a link): the work directory and the lock are
# named after OUTDIR, and two spellings must not give two of each. The directory itself when it exists, else its parent and the name.
# the physical working directory: pwd -P where the shell has it (dash, bash); the Bourne shell of Solaris 10 has no logical pwd to undo
phys() { x=`pwd -P 2>/dev/null`; if [ -n "$x" ]; then printf '%s\n' "$x"; else pwd; fi; }
canon() {
    p=`printf '%s\n' "$1" | sed -e 's|//*|/|g' -e 's|/\./|/|g' -e 's|/\.$||' -e 's|/$||'`
    [ -n "$p" ] || p=/
    if [ -d "$p" ]; then ( cd "$p" && phys ); return; fi
    d=`dirname "$p"`; n=`basename "$p"`
    if [ -d "$d" ]; then printf '%s/%s\n' "`cd "$d" && phys`" "$n" | sed 's|^//|/|'; else printf '%s\n' "$p"; fi
}
# the directory as the shell sees it (symlinks resolved) when it exists, else as given
real() {
    if [ -d "$1" ]; then ( cd "$1" && pwd ); else printf '%s\n' "$1"; fi
}
have() { [ -f "$1" ] || [ -d "$1" ] || [ -h "$1" ]; }

cmd=$1; [ $# -gt 0 ] && shift
case "$cmd" in
path)
    out=$1; over=$2
    if [ -n "$over" ]; then absolute "$over"; exit 0; fi
    out=`canon \`absolute "$out"\``
    base=${TMPDIR:-/var/tmp}
    # printf with \n: Solaris' sed drops a last line that has none. A TMPDIR of / is no place for this either.
    base=`printf '%s\n' "$base" | sed 's|/*$||'`
    [ -n "$base" ] || base=/var/tmp
    uid=`id | sed 's/^uid=\([0-9]*\).*/\1/'`
    # The sum is up to 4294967295: Solaris' awk clamps printf %d at 2147483647, so the digits are padded as a string.
    n=`printf '%s %s' "$uid" "$out" | cksum | awk '{ s = $1; while (length(s) < 10) s = "0" s; print s }'`
    printf '%s/sun4v-qemu-kit.%s\n' "$base" "$n"
    ;;
make)
    wd=$1; src=$2; out=$3
    bad=
    case "$wd" in
    "") echo "WORKDIR is empty"; exit 1 ;;
    /*) ;;
    *) echo "WORKDIR must be an absolute path, got '$wd'"; exit 1 ;;
    esac
    case "$wd" in
    *" "*|*"	"*) echo "refusing WORKDIR=$wd: it has a space or a tab in it. WORKDIR must be a path without one"; exit 1 ;;
    esac
    if [ -h "$wd" ]; then echo "refusing WORKDIR=$wd: it is a symbolic link"; exit 1; fi
    rw=`real "$wd"`; rs=`real "$src"`; ro=`real "$out"`
    if [ "$rw" = / ]; then bad="is /"; fi
    if [ "$rw" = "$HOME" ]; then bad="is your home directory"; fi
    case "$rs/" in "$rw"/*) bad="is the source tree or contains it" ;; esac
    case "$ro/" in "$rw"/*) bad="is OUTDIR or contains it" ;; esac
    case "$rw/" in "$ro"/*) bad="is inside OUTDIR (OUTDIR holds the firmware set only)" ;; esac
    if [ -z "$bad" ] && [ -d "$wd" ]; then
        # Whoever made the directory can put the marker in it: take an existing one only if it is yours and not writable by
        # others (the name is predictable, in a shared /var/tmp). ls -ldn: numeric owner on Solaris and GNU alike.
        uid=`id | sed 's/^uid=\([0-9]*\).*/\1/'`
        wd_owner=`ls -ldn "$wd" | awk '{ print $3 }'`; wd_perm=`ls -ldn "$wd" | awk '{ print $1 }'`
        if [ "$wd_owner" != "$uid" ]; then bad="is owned by uid $wd_owner, not by you"
        else
            case "$wd_perm" in ?????w*|????????w*) bad="is writable by group or others (chmod go-w it)" ;; esac
        fi
    fi
    if [ -z "$bad" ] && [ -d "$wd" ]; then
        if have "$wd/$MARK"; then :; else
            if [ -n "`ls -a "$wd" 2>/dev/null | sed -e '/^\.$/d' -e '/^\.\.$/d'`" ]; then
                bad="is not empty and was not made by this build (no $MARK in it)"
            fi
        fi
    fi
    if [ -n "$bad" ]; then
        echo "refusing WORKDIR=$wd: it $bad. WORKDIR must be a directory of its own."
        exit 1
    fi
    [ "${4:-}" = check ] && exit 0        # a dry run (make -n) judges the directory and makes nothing
    ( umask 077; mkdir -p "$wd" && : > "$wd/$MARK" ) || { echo "cannot create WORKDIR=$wd"; exit 1; }
    ;;
clean)
    wd=$1; src=$2
    [ -n "$wd" ] || exit 0
    have "$wd" || exit 0
    if [ -h "$wd" ]; then echo "workdir: $wd is a symbolic link; not removed" >&2; exit 0; fi
    if have "$wd/$MARK"; then :; else
        echo "workdir: $wd was not made by this build (no $MARK); not removed" >&2
        exit 0
    fi
    rw=`real "$wd"`; rs=`real "$src"`
    case "$rw" in /|"$HOME") echo "workdir: refusing to remove $rw" >&2; exit 0 ;; esac
    case "$rs/" in "$rw"/*) echo "workdir: $rw is the source tree or contains it; not removed" >&2; exit 0 ;; esac
    rm -rf "$wd"
    echo "removed $wd"
    ;;
*)
    echo "usage: workdir.sh path OUTDIR [WORKDIR] | make WORKDIR SRC OUTDIR [check] | clean WORKDIR SRC" >&2
    exit 2
    ;;
esac
exit 0
