# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# fbwork.sh -- sourced by the forth_bootstrap scripts: sets W, their work directory, and refuses one that is not yours.
#   Env: FB_WORK (default ${TMPDIR:-/tmp}/niagara-forth-bootstrap-<your uid>).
# W holds a clone of cforth and the programs built from it, which the scripts then run (cforth's own `forth`). A directory that
# somebody else made in a shared /tmp, or left writable for others, would run that person's files as you: so it must be a
# directory of yours, not a symbolic link, and not writable by group or others.
W=${FB_WORK:-${TMPDIR:-/tmp}/niagara-forth-bootstrap-`id -u`}
case "$W" in /*) ;; *) W=`pwd`/$W ;; esac       # the scripts change directory: a relative path would point somewhere else
if [ ! -e "$W" ]; then ( umask 077; mkdir -p "$W" ) || { echo "fbwork: cannot create $W" >&2; exit 1; }; fi
if [ -L "$W" ] || [ ! -d "$W" ]; then echo "fbwork: $W is a symbolic link or not a directory; refusing (FB_WORK=<a directory of your own>)" >&2; exit 1; fi
if [ ! -O "$W" ]; then echo "fbwork: $W is not owned by you; refusing (FB_WORK=<a directory of your own>)" >&2; exit 1; fi
if [ -n "`find "$W" -maxdepth 0 -perm /022 2>/dev/null`" ]; then echo "fbwork: $W is writable by group or others; refusing (chmod go-w $W)" >&2; exit 1; fi
