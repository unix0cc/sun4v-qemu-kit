#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# The build stamp every firmware build bakes in -- openboot.bin's version.fth
# and q.bin's version string, on both toolchains -- from one place, so the
# builds cannot disagree. Prints shell assignments for the caller to eval:
#
#   STAMP_REV          short commit hash, -dirty if tracked files differ
#                      from HEAD
#   STAMP_EPOCH        the stamp's time, seconds since 1970
#   STAMP_RELEASE      0.1 when HEAD is exactly tag v0.1 and the tree is
#                      clean, else empty
#   STAMP_OBP_RELEASE  OBP's obp-release: 4.x.build_122+qemu, plus
#                      -$STAMP_RELEASE on a release tag
#   STAMP_MDY_HM       09/28/26 23:46   (version.fth's sub-release)
#   STAMP_YMD          2026/09/28       (q.bin, Makefile.family's DATE)
#   STAMP_HM           23:46            (q.bin, Makefile.family's TIME)
#   STAMP_TD           version.fth's compile-signature, as the Forth that
#                      packs it: td <min> td <hour> bwjoin ... lxjoin
#
# STAMP_EPOCH is SOURCE_DATE_EPOCH if the caller set it
# (https://reproducible-builds.org/specs/source-date-epoch/), else the commit
# date of a clean HEAD -- so two builds of one commit stamp the same bytes.
# A dirty tree gets the current time instead: the commit date says nothing
# about what was built, and such a build is not reproducible anyway.
#
# Every date field is formatted here, in UTC, so no caller needs a date(1)
# that can format an arbitrary time: GNU date -d @N where it exists, perl's
# POSIX strftime where it does not (Solaris 10: /usr/bin/perl, 5.8). Local
# time would make the bytes depend on the builder's TZ.
#
# Written for Solaris' Bourne /bin/sh as well as dash/bash: no $( ),
# no ${x#y}, no ${x:?}. The sun path runs this under Solaris userland.
#
# Only v[0-9]* tags name a release; any other tag is not a release and must not match.
#
# Usage: eval "`build/stamp.sh <repo>`"
set -e
REPO=$1
[ -n "$REPO" ] || { echo "usage: stamp.sh <repo>" >&2; exit 2; }

REV=`git -C "$REPO" rev-parse --short HEAD 2>/dev/null || true`
CLEAN=
if [ -z "$REV" ]; then
    REV=unknown
elif git -C "$REPO" diff --quiet HEAD -- 2>/dev/null; then
    CLEAN=1
else
    REV=$REV-dirty
fi

# GNU date is recognised by --version; Solaris date rejects the option and
# formats nothing. Never probe with bare arguments: on Solaris
# `date mmddHHMM` SETS the clock.
if date --version >/dev/null 2>&1; then GNUDATE=1; else GNUDATE=; fi

now() {
    if [ -n "$GNUDATE" ]; then date +%s
    else perl -e 'print time, "\n"'; fi
}
fmt() {  # fmt <strftime format>
    if [ -n "$GNUDATE" ]; then date -u -d "@$EPOCH" "+$1"
    else perl -MPOSIX -e 'print strftime($ARGV[0], gmtime($ARGV[1])), "\n"' "$1" "$EPOCH"; fi
}

if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    EPOCH=$SOURCE_DATE_EPOCH
elif [ -n "$CLEAN" ]; then
    EPOCH=`git -C "$REPO" log -1 --format=%ct HEAD`
else
    EPOCH=`now`
fi

RELEASE=
if [ -n "$CLEAN" ]; then
    TAG=`git -C "$REPO" describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null || true`
    # The output of this script is eval'd by its callers, and a tag name may hold quotes, `;` and `$`: take only a plain version.
    case $TAG in
    *[!A-Za-z0-9._+-]*) echo "stamp.sh: ignoring tag with characters other than A-Za-z0-9._+-" >&2; TAG= ;;
    esac
    [ -z "$TAG" ] || RELEASE=`echo "$TAG" | sed 's/^v//'`
fi
OBP_RELEASE=4.x.build_122+qemu
[ -z "$RELEASE" ] || OBP_RELEASE=$OBP_RELEASE-$RELEASE

echo "STAMP_REV='$REV'"
echo "STAMP_EPOCH='$EPOCH'"
echo "STAMP_RELEASE='$RELEASE'"
echo "STAMP_OBP_RELEASE='$OBP_RELEASE'"
echo "STAMP_MDY_HM='`fmt '%m/%d/%y %H:%M'`'"
echo "STAMP_YMD='`fmt '%Y/%m/%d'`'"
echo "STAMP_HM='`fmt '%H:%M'`'"
echo "STAMP_TD='`fmt 'td %M td %H bwjoin td %d td %m bwjoin wljoin td %Y lxjoin'`'"
