#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# aschk.sh -- the GNU build runs Sun's aschk on the assembler sources, and that aschk can fail.
#
# On the sun path `q: chkasm` (greatlakes/*/Makefile.platform) runs aschk before the link: it checks each
# load and store in the .s files that names an offsets.h constant against offsets.chk, the size and the
# type of the field, and the build stops on a mismatch. build/hv_reset/gnu/build.sh does the same, with
# aschk built from Sun's source (patches/hv/gnu/aschk-host-build.patch). Two things can go quietly wrong
# there, and this test is for both:
#
#   - the step is skipped or does nothing: a checker that has never been seen to fail proves nothing.
#     So the test changes the recorded size of CONFIG_MEMSIZE in a copy of offsets.chk from 8 to 4 and
#     runs the built aschk on the sources: it must exit non-zero and name CONFIG_MEMSIZE (main.s does a
#     stx to it, an 8-byte access).
#   - the unchanged offsets.chk is reported against: the build would have stopped, so the test also
#     requires the build's own run (aschk.log) to be empty and its line in build.log.
#
# Measured: against the unmodified offsets.chk it prints nothing and exits 0; with CONFIG_MEMSIZE's size
# 4 it exits 1 with "main.s:212 : Warning: access size mismatch using symbol 'CONFIG_MEMSIZE'" (and
# main.s:1486), "Completed with 2 warnings".
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
: "${OUTDIR:?set OUTDIR}"
"$HERE/../lib/build.sh"
PLATFORM=${PLATFORM:-ontario}
T2=$REPO/src/hypervisor/src

[ -x "$OUTDIR/aschk/aschk" ] || { echo "FAIL: the build made no aschk ($OUTDIR/aschk/aschk)" >&2; exit 1; }
[ -f "$OUTDIR/aschk.log" ] || { echo "FAIL: the build did not run aschk (no $OUTDIR/aschk.log)" >&2; exit 1; }
[ ! -s "$OUTDIR/aschk.log" ] || { echo "FAIL: aschk reports against the build's own offsets.chk:" >&2; cat "$OUTDIR/aschk.log" >&2; exit 1; }
grep -q '^aschk: the assembler sources match offsets.chk' "$OUTDIR/build.log" \
    || { echo "FAIL: build.log has no aschk line" >&2; exit 1; }

# the control: a wrong size for a field that the sources access with 8 bytes
bad=$(mktemp "${TMPDIR:-/tmp}/aschk-bad.XXXXXX")
trap 'rm -f "$bad"' EXIT
sed -E 's/^(u[[:space:]]+0x[0-9a-f]+[[:space:]]+)0x8([[:space:]]+CONFIG_MEMSIZE)$/\10x4\2/' "$OUTDIR/offsets.chk" > "$bad"
cmp -s "$bad" "$OUTDIR/offsets.chk" \
    && { echo "FAIL: no 8-byte CONFIG_MEMSIZE entry in offsets.chk to change -- the control has nothing to bite on" >&2; exit 1; }
out=$(cd "$T2" && "$OUTDIR/aschk/aschk" -u -s -n "$bad" \
      greatlakes/$PLATFORM/src/*.s greatlakes/common/src/*.s greatlakes/$PLATFORM/dumbreset/*.s common/src/*.s 2>&1) && rc=0 || rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: aschk accepted CONFIG_MEMSIZE with a wrong size (exit 0): it checks nothing" >&2; exit 1; }
case "$out" in *CONFIG_MEMSIZE*) ;; *) echo "FAIL: aschk failed (exit $rc) but not on CONFIG_MEMSIZE:" >&2; echo "$out" >&2; exit 1;; esac
echo "ok: the build ran aschk (no report), and aschk rejects a wrong CONFIG_MEMSIZE size (exit $rc)"
