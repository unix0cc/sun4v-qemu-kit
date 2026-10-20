#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# tests/negative.sh -- negative control for check-seed.sh: a check that cannot fail proves nothing.
# One constant in one Forth source (fm/kernel/stresc.fth, $cat: d# 255 -> d# 254) is changed in a COPY of
# src/obp/obp (the tree itself is never touched); check-seed.sh run against that copy must NOT report the seed as
# reproduced. Exit 0 = the check can fail; 1 = it accepted the modified source, or failed without comparing; 77 = skip.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd); REPO=$(cd "$HERE/.." && pwd)
. "$HERE/fbwork.sh"
N=$W/negative; rm -rf "$N"; mkdir -p "$N"; cp -a "$REPO/src/obp/obp" "$N/obp"
F=$N/obp/fm/kernel/stresc.fth
sed -i 's/d# 255 swap/d# 254 swap/' "$F"
if cmp -s "$F" "$REPO/src/obp/obp/fm/kernel/stresc.fth"; then echo "negative: the edit changed nothing in $F" >&2; exit 1; fi
FB_BP=$N/obp "$HERE/check-seed.sh" >"$N/out.log" 2>&1; rc=$?
if [ $rc = 77 ]; then echo "SKIP (check-seed.sh skipped)"; exit 77; fi
if [ $rc = 0 ]; then echo "negative: FAIL -- check-seed.sh accepted the modified source" >&2; exit 1; fi
# Any other failure of check-seed.sh (a build that broke, no listings) is not the control working: it must have compared and found a difference.
if ! grep -q DIFFERENT "$N/out.log"; then echo "negative: FAIL -- check-seed.sh failed (rc $rc) without reporting a difference, so the control proves nothing; see $N/out.log" >&2; exit 1; fi
echo "negative: ok -- with one constant changed in fm/kernel/stresc.fth, check-seed.sh fails (rc $rc):"
grep -E "DIFFERENT|FAIL" "$N/out.log" | head -3
