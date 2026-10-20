#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# build.sh -- cross-build cforth for sparc32 (big-endian, 4-byte cells, 32-bit tokens): the host Forth for step 1.
#   Needs sparc64-linux-gnu-gcc (-m32 -static) and a way to run sparc32 binaries, in practice a binfmt_misc handler (the Makefile
#   runs its own ./meta and ./forth), i.e. the same qemu-user setup as REQUIREMENTS.LINUX asks for.
#   Exit 77 = SKIP (a requirement is missing, said so on stderr). Prints the build directory.
#   cforth's own sources are not changed; the one Makefile line is edited in a copy of its build directory:
#   CONFIG += -DBITS32 -DT16  ->  -DBITS32   (16-bit tokens on SPARC alignment rules: "Address exception").
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/fbwork.sh"
CC=${FB_CC:-sparc64-linux-gnu-gcc}
skip() { echo "SKIP: $*" >&2; exit 77; }
command -v "$CC" >/dev/null || skip "no $CC"
# Not "is a handler listed in /proc/sys/fs/binfmt_misc": a container does not see that directory but runs the host's handlers
# (flag F). What matters is that a sparc32 binary runs.
P=$(mktemp -d "${TMPDIR:-/tmp}/fb-probe.XXXXXX"); trap 'rm -rf "$P"' EXIT
echo 'int main(void) { return 0; }' > "$P/p.c"
"$CC" -m32 -static "$P/p.c" -o "$P/p" 2>/dev/null && "$P/p" 2>/dev/null \
    || skip "a sparc32 binary does not run here: no qemu-sparc32plus binfmt_misc handler (cforth's Makefile runs the SPARC binaries it builds)"
"$HERE/fetch.sh" >&2
D=$W/cforth/build/host-serial-sparc32
if [ ! -s "$D/app.dic" ]; then
    rm -rf "$D"; cp -a "$W/cforth/build/host-serial-linux" "$D"
    sed -i 's/^\(CONFIG += -DBITS32\) -DT16/\1/' "$D/Makefile"
    grep -q -- '-DT16' "$D/Makefile" && { echo "build: -DT16 still in $D/Makefile" >&2; exit 1; }
    # A failed build is an error, not a skip: 77 is for a missing requirement, and the make targets turn 77 into success.
    ( cd "$D" && make CC="$CC -m32 -static" >"$W/cforth-build.log" 2>&1 ) \
        || { echo "build: cforth did not build for sparc32; the end of $W/cforth-build.log:" >&2; tail -20 "$W/cforth-build.log" >&2; exit 1; }
fi
echo "$D"
