#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# dict-dump.sh -- functional/content check for a stand.dic: list every word
# in every vocabulary (dict-dump.fth, using the dictionary's own `words`),
# normalized to one word per line, sorted within each vocabulary section.
#
# Complements byte comparison (compare-reference.sh) rather than replacing it:
# a .dic/stand.dic image differs by construction between engine binaries
# (engine-binary-address class, dic-images-embed-engine-binary-addresses
# memory) even when nothing about the OBP source or the tokenized dropins
# changed, so hashing raw stand.dic bytes into a regression gate produces
# false failures on every legitimate toolchain change. Word names carry no
# addresses, so this hash should be stable across such changes and only
# move on an actual change to the dictionary's content -- a real regression
# a byte manifest cannot tell apart from a harmless recompile.
#
# Usage: dict-dump.sh <stand.dic>
# Output: normalized word list on stdout; "sha256 <hash>" on the last stderr
# line for quick eyeballing (the real comparison is `cmp`/`diff` on stdout,
# or two invocations piped through `sha256sum`).
set -eu
# Stdin MUST be redirected: the engine's -s script runs to `bye`, but if
# something along the way falls back to an interactive read it inherits this
# shell's real tty (fd 0) under qemu-sparc64-static and blocks forever
# waiting for a keystroke that never comes -- silent, 0% CPU, indistinguishable
# from a real hang without checking `ls -l /proc/<pid>/fd/0`. Measured
# Measured: `make obp-verify` hung in this test that way once; the identical
# invocation with stdin from /dev/null runs to completion in under a second.
: "${QEMU_SPARC64:?set to the qemu-sparc64 linux-user binary}"
: "${FORTH64_BIN:?set to the cross-built forth64 binary}"
DIC=${1:?usage: dict-dump.sh <stand.dic>}
HERE=$(cd "$(dirname "$0")" && pwd)
# the temporary file goes to TMPDIR: the source tree may be read-only
TMPF=$(mktemp "${TMPDIR:-/tmp}/dict-dump.XXXXXX") || exit 2
trap 'rm -f "$TMPF"' EXIT
raw=$("$QEMU_SPARC64" "$FORTH64_BIN" -d "$DIC" -D SUN4V -s "fload $HERE/dict-dump.fth" < /dev/null 2>/dev/null)
printf '%s\n' "$raw" | awk '
    /::$/ { if (sec != "") flush(); sec = $0; sub(/ ::$/, "", sec); n = 0; next }
    sec != "" { for (i = 1; i <= NF; i++) w[n++] = $i }
    function flush(   i) {
        asort_words(); print "== " sec " =="
        for (i = 0; i < n; i++) print w[i]
        print ""
    }
    function asort_words(   i, j, t) {
        for (i = 1; i < n; i++) { t = w[i]; j = i - 1
            while (j >= 0 && w[j] > t) { w[j+1] = w[j]; j-- }
            w[j+1] = t }
    }
    END { if (sec != "") flush() }
' | tee /dev/null > "$TMPF"
cat "$TMPF"
sha256sum "$TMPF" | awk '{print "sha256 " $1}' >&2
rm -f "$TMPF"
