#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# fetch.sh -- clone cforth at the pinned commit into $FB_WORK/cforth (not vendored: the tree carries none of it).
#   Env: FB_WORK (default ${TMPDIR:-/tmp}/niagara-forth-bootstrap-<uid>; see fbwork.sh), CFORTH_URL.
# The pinned commit is the last one that builds a host image: HEAD (f5cff86 at the time) hardcodes
# ../../build/esp32-extra/vars.h in src/cforth/forth.h. GIT_CONFIG_GLOBAL=/dev/null keeps a global
# "url.<ssh>.insteadOf https://github.com" rewrite from turning this into an ssh clone.
set -eu
PIN=353a969f07027361f44b3ff9c5b7059be5780274
URL=${CFORTH_URL:-https://github.com/MitchBradley/cforth}
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/fbwork.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
mkdir -p "$W"
if [ ! -d "$W/cforth/.git" ]; then git clone -q "$URL" "$W/cforth"; fi
git -C "$W/cforth" checkout -q "$PIN"
[ "$(git -C "$W/cforth" rev-parse HEAD)" = "$PIN" ] || { echo "fetch: cforth is not at $PIN" >&2; exit 1; }
echo "cforth $PIN in $W/cforth"
