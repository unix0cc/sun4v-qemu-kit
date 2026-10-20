#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# release.sh <OUT> -- build the firmware release tarball from a CLEAN COMMIT.
#
#   make release            -> $(RELEASE_OUT)/sun4v-qemu-kit-<rev>.tar.gz  (+ .sha256)
#   make release-check      builds it twice and compares the two tarballs
#
# What goes in: for every configuration in RELEASE_TARGETS the six files QEMU's niagara machine asks for
# (reset.bin q.bin openboot.bin nvram1 1up-md.bin 1up-hv.bin), the licence texts, the READMEs, a
# SHA256SUMS over all of it and a RELEASE-INFO that records how it was built. Nothing from Oracle's S10image.
# What is true of the machine that built it (kernel, qemu-user versions) is not in the tarball: it goes to
# $NAME.build-env beside it, so that the tarball does not change with the build host's kernel.
#
# Why a clone of HEAD, and not a build in the working tree:
#   * the build stamps `-dirty` into every banner when tracked files differ from HEAD (build/stamp.sh); a
#     release must carry the clean commit's stamp and date, so the build runs on a fresh clone of HEAD.
#   * the build directory's path must not reach the images, and it does not: q.bin compiles with -fmacro-prefix-map
#     (build/hv_reset/gnu/build.sh), and openboot.bin is built in a scratch directory of fixed length (build/obp/gnu/build-obp.sh;
#     the OBP engines take addresses from the length of their paths). Measured 2026-10-08: the same tarball for RELEASE_ROOT of 11 and
#     about 60 characters. RELEASE_ROOT is only where the clone lives (default ${TMPDIR:-/tmp}/sun4v-qemu-kit-release-<uid>; wiped).
# The tarball is deterministic (sorted names, mtime = commit time, uid/gid 0, gzip -n).
#
# Which configurations: RELEASE_TARGETS, default "legion pci" (decided 2026-10-07). Every name listed must be an md/<target>/ with a 1up.pdesc.
# Env: RELEASE_TARGETS (default "legion pci"), RELEASE_ROOT (default ${TMPDIR:-/tmp}/sun4v-qemu-kit-release-<uid>; wiped), RELEASE_ALLOW_DIRTY=1 (build HEAD anyway, and
#      say so in the file name -- never publish that), OBP_SEED (passed through: forth.dic | kernel-xref).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT=${1:?usage: release.sh <OUT>}
ROOT=${RELEASE_ROOT:-${TMPDIR:-/tmp}/sun4v-qemu-kit-release-$(id -u)}
CONFIGS=${RELEASE_TARGETS:-legion pci}
FIRMWARE="reset.bin q.bin openboot.bin nvram1 1up-md.bin 1up-hv.bin"
DOCS="README README.USAGE README.S10U11 AUTHORS LICENSE LICENSE_CODE LICENSE.BSD-2-Clause BSD+_License_OpenSPARCT2.txt"

cd "$REPO"
SUFFIX=
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    [ "${RELEASE_ALLOW_DIRTY:-}" = 1 ] || { echo "release: tracked files differ from HEAD; commit or stash them (or RELEASE_ALLOW_DIRTY=1 for a throwaway)" >&2; exit 2; }
    SUFFIX=-DIRTY-NOT-A-RELEASE
fi
COMMIT=$(git rev-parse HEAD); REV=$(git rev-parse --short=12 HEAD)
EPOCH=$(git log -1 --format=%ct HEAD)
NAME=sun4v-qemu-kit-$REV$SUFFIX

# $ROOT is removed below, so accept only a directory this script would name itself: the last component must start with
# sun4v-qemu-kit, and it must not be a symlink (a guard on a list of bad paths misses /root, /var, /home/user ...).
ROOT=${ROOT%/}
case "${ROOT##*/}" in sun4v-qemu-kit*) ;; *) echo "release: RELEASE_ROOT must end in sun4v-qemu-kit* (it is removed first); refusing '$ROOT'" >&2; exit 2;; esac
# ... and not the clone this script runs from, nor a directory that holds it or lies inside it (rm -rf below)
_r=$(readlink -f "$ROOT") || _r=$ROOT; _s=$(readlink -f "$REPO")
case "$_r/" in "$_s"/*) echo "release: RELEASE_ROOT=$ROOT is the repository or inside it; refusing" >&2; exit 2;; esac
case "$_s/" in "$_r"/*) echo "release: RELEASE_ROOT=$ROOT holds the repository; refusing" >&2; exit 2;; esac
[ ! -L "$ROOT" ] || { echo "release: RELEASE_ROOT=$ROOT is a symlink; refusing" >&2; exit 2; }
# The default name is predictable and /tmp is shared: a directory somebody else made there would be built in (git hooks in
# its clone, a planted configure) or could not be removed. Remove only one that is yours; make the new one private, and fail
# if it already exists again (mkdir without -p) instead of building in it.
if [ -e "$ROOT" ] && [ ! -O "$ROOT" ]; then echo "release: $ROOT exists and is not yours; refusing (RELEASE_ROOT=<a path of your own>)" >&2; exit 2; fi
rm -rf "$ROOT"; mkdir -p "$(dirname "$ROOT")"; mkdir -m 700 "$ROOT" || { echo "release: cannot create $ROOT" >&2; exit 2; }
# -c init.defaultBranch: a clone of a detached HEAD (a clean-room checkout) makes git 2.4x print the "initial branch name" hint
git -c init.defaultBranch=main clone -q --no-hardlinks "$REPO" "$ROOT/src"
git -C "$ROOT/src" checkout -q "$COMMIT"
export SOURCE_DATE_EPOCH=$EPOCH
# A clean clone has no config.auto.mk: configure it as a user would. Without it the host and cross compilers get no
# -std=gnu17, and mdgen / the OBP host tools fail on a gcc whose default is C23 (Ubuntu 26.04, gcc 15).
: > "$ROOT/build.log"
( cd "$ROOT/src" && ./configure ) >> "$ROOT/build.log" 2>&1 \
    || { echo "release: ./configure failed in the clean clone, see $ROOT/build.log" >&2; tail -20 "$ROOT/build.log" >&2; exit 1; }

for c in $CONFIGS; do [ -f "$ROOT/src/md/$c/1up.pdesc" ] || { echo "release: RELEASE_TARGETS names $c, but md/$c/1up.pdesc does not exist" >&2; exit 2; }; done
echo "=== release $REV: building $CONFIGS in $ROOT/src (clean clone of HEAD) ==="
for c in $CONFIGS; do
    ( cd "$ROOT/src" && make TARGET=$c OUTDIR="$ROOT/src/output/$c" ) >> "$ROOT/build.log" 2>&1 \
        || { echo "release: build of $c failed, see $ROOT/build.log" >&2; tail -20 "$ROOT/build.log" >&2; exit 1; }
    ( cd "$ROOT/src" && make workdir-clean TARGET=$c OUTDIR="$ROOT/src/output/$c" ) >> "$ROOT/build.log" 2>&1 || true
done

STAGE=$ROOT/stage/$NAME
mkdir -p "$STAGE"
cfgs=$CONFIGS
[ -n "$cfgs" ] || { echo "release: RELEASE_TARGETS is empty" >&2; exit 1; }
BUILT=$ROOT/src/output
for c in $cfgs; do
    mkdir -p "$STAGE/$c"
    for f in $FIRMWARE; do
        [ -f "$BUILT/$c/$f" ] || { echo "release: $BUILT/$c/$f missing" >&2; exit 1; }
        cp "$BUILT/$c/$f" "$STAGE/$c/$f"
    done
done
[ -f "$ROOT/src/AUTHORS" ] || { echo "release: AUTHORS is missing (the licence refers to it)" >&2; exit 1; }
for f in $DOCS; do [ -f "$ROOT/src/$f" ] && cp "$ROOT/src/$f" "$STAGE/$f"; done
# 1up-md.bin and 1up-hv.bin are GPL-2 object code (LICENSE_CODE): the sources they were compiled from and the licence text go with
# them, all of md/ (GPLv2 section 3(a)); the licence text stays at md/GPLv2_License_OpenSPARCT1.txt, where LICENSE refers to it.
[ -f "$ROOT/src/md/GPLv2_License_OpenSPARCT1.txt" ] || { echo "release: md/GPLv2_License_OpenSPARCT1.txt is missing" >&2; exit 1; }
"$HERE/pack-md.sh" "$ROOT/src" "$STAGE"

# the RAM each configuration was built for (-m must equal it): 4th field of .md-signature, written by the build
memcfg=
for c in $cfgs; do
    m=$(cut -d'|' -f4 "$BUILT/$c/.md-signature" 2>/dev/null) || m=
    [ -n "$m" ] || { echo "release: no MD_MEM in $BUILT/$c/.md-signature" >&2; exit 1; }
    memcfg="$memcfg${memcfg:+, }$c ${m} MB"
done

{
    echo "sun4v-qemu-kit release $REV"
    echo "commit        $COMMIT"
    echo "commit time   $(date -u -d @"$EPOCH" +%Y-%m-%dT%H:%M:%SZ)  (SOURCE_DATE_EPOCH=$EPOCH)"
    echo "configs       $(echo $cfgs)"
    echo "toolchain     gnu: $(sparc64-linux-gnu-gcc --version | head -1)"
    echo "obp seed      ${OBP_SEED:-forth.dic}"
    echo "memory        $memcfg   (-m must equal it)"
    echo "rebuild       from the commit above with the toolchain above; the build path does not change the files (see <name>.build-env)"
    [ -n "$SUFFIX" ] && echo "WARNING       built with RELEASE_ALLOW_DIRTY; not a release"
    echo
    echo "boot:  qemu-system-sparc64 -M niagara -L <this dir>/<target> -m <that config's MB, see memory above> -nographic"
    echo
    echo "legion boots to the OpenBoot ok prompt (tests/smoke) and to Solaris's login prompt (tests/full/login) on a stock QEMU at its default 2048 MB."
    echo "An earlier measurement of the RAM sizes, on a build of legion made before the MDs were trimmed, one boot per cell, guest disk.s10hw2 (Solaris 10, hsimd driver), -accel tcg,thread=single:"
    echo "  QEMU 8.2.2 (distro) and upstream master f9587d4045 (2026-10-06): login prompt at 256 and 2048 MB; panic in unix:startup_vm at 3072 and 4096 MB."
    echo "  Master plus the TTE page-size patch (for 32M/256M pages; not in upstream: qemu-devel 2026-09-18, <20260918105705.433093-1-sun4qemu@gmail.com>): login prompt at 256, 2048, 3072 and 4096 MB."
    echo "  OBP-loader 'Level 14' flake, boot disk, 2048 MB: 0 of 100 boots on each of the three (disk path only)."
    echo "Of those, only 2048 MB was repeated on the final tree."
    echo "pci needs a QEMU with vpci and cmd646 support (not in upstream yet); it boots to Solaris 10's login prompt at 4096 MB on such a QEMU."
} > "$STAGE/RELEASE-INFO"
( cd "$STAGE" && find . -type f ! -name SHA256SUMS | LC_ALL=C sort | sed 's|^\./||' | xargs sha256sum > SHA256SUMS )

mkdir -p "$OUT"
{   echo "build host of $NAME (not part of the tarball)"
    echo "build root    $ROOT/src"
    emu() { for q in "$1-static" "$1"; do command -v "$q" >/dev/null 2>&1 && { "$q" --version | head -1; return; }; done; }
    echo "emulators     $(emu qemu-sparc64) / $(emu qemu-sparc32plus)"
    echo "host          $(uname -srm)"
} > "$OUT/$NAME.build-env"
TAR=$OUT/$NAME.tar.gz
tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 --numeric-owner --mode='u=rwX,go=rX' -C "$ROOT/stage" -cf - "$NAME" | gzip -n -9 > "$TAR"
( cd "$OUT" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256" )
echo "release: $TAR"; cat "$OUT/$NAME.tar.gz.sha256"
