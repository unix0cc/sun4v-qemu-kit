#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# The graph an MD encodes. mdlint checks only the element sequence and passes a dangling arc.
# For OUR blobs every finding of lib/mdgraph.py is a failure:
#   target  an arc points at something that is not a node
#   root    not exactly one node named root
#   pair    a fwd arc without the matching back arc, or a back arc without its fwd
#           FWARC 2005/115, md-info section 3.1: "for every node A that has a fwd arc pointing to another node B,
#           there is a corresponding back arc for node B pointing back to A". illumos walks the back arcs
#           (sun4v/os/fillsysinfo.c:250,333,1234). Later Solaris follows the text more strictly than HW1-era 10 did.
#   reach   a node the root cannot reach along fwd arcs (outside the DAG the spec describes)
# The hv MD is not covered by 2005/115 (the hypervisor's parser, mdsup.c, filters by node type); the same rules are applied
# to it as our own convention.
# Sun's shipped binaries are checked for target/root only, if the T1 tree is there (T1=): they are HW1-era and DO violate pair/reach.
. "$(dirname "$0")/../lib/env.sh"
build_ours
n=0
for c in $CONFIGS; do for t in md hv; do
    out=$(python3 "$HERE/lib/mdgraph.py" "$OUT/$c/1up-$t.bin" --plain 2>/dev/null) && rc=0 || rc=$?
    [ "$rc" = 0 ] || { echo "FAIL: $c-$t:" >&2; echo "$out" | sed 's/^/    /' >&2; exit 1; }
    n=$((n+1))
done; done
# The checker itself: hand-made broken MDs must be reported as findings, never as a traceback.
bad="$OUT/graph-bad"; mkdir -p "$bad"
python3 - "$bad" <<'PY'
import struct, sys
def md(path, els):
    names = b'root\0fwd\0'; off = {'root': 0, 'fwd': 5}
    nodes = b''
    for tag, nm, val in els:
        nodes += struct.pack('>BBHI', ord(tag), 0, 0, off.get(nm, 0)) + struct.pack('>Q', val)
    open(path, 'wb').write(struct.pack('>IIII', 0x10000, len(nodes), len(names), 0) + nodes + names)
d = sys.argv[1]
md(d + '/arc-after-end.bin',   [('N', 'root', 0), ('E', '', 0), ('a', 'fwd', 0)])        # arc outside any node
md(d + '/arc-before-node.bin', [('a', 'fwd', 99), ('N', 'root', 0), ('E', '', 0)])       # ... with a bad target too
md(d + '/arc-dangling.bin',    [('N', 'root', 0), ('a', 'fwd', 99), ('E', '', 0)])       # inside a node, past the end
PY
for f in arc-after-end:owner arc-before-node:owner arc-dangling:target; do
    out=$(python3 "$HERE/lib/mdgraph.py" "$bad/${f%%:*}.bin" --plain 2>&1) && rc=0 || rc=$?
    case "$out" in *Traceback*) echo "FAIL: mdgraph crashed on ${f%%:*}:" >&2; echo "$out" | sed 's/^/    /' >&2; exit 1;; esac
    [ "$rc" = 1 ] && echo "$out" | grep -q "^${f##*:}:" || { echo "FAIL: mdgraph on ${f%%:*}: want exit 1 and a '${f##*:}:' finding, got exit $rc: $out" >&2; exit 1; }
done
sun="Sun's binaries skipped (no T1 tree)"
if [ -n "$T1" ] && [ -f "$T1/S10image/1up-md.bin" ]; then
    for cfg in 1up 1g2p 1g32p; do for t in md hv; do
        out=$(python3 "$HERE/lib/mdgraph.py" "$T1/S10image/$cfg-$t.bin" --plain 2>&1) && rc=0 || rc=$?
        case "$out" in *Traceback*) echo "FAIL: mdgraph crashed on sun $cfg-$t:" >&2; echo "$out" | sed 's/^/    /' >&2; exit 1;; esac
        [ "$rc" -le 1 ] || { echo "FAIL: mdgraph on sun $cfg-$t: exit $rc: $out" >&2; exit 1; }
        echo "$out" | grep -qE '^(target|root):' && { echo "FAIL: sun $cfg-$t has a target/root finding" >&2; exit 1; } || true
    done; done; sun="Sun's 6: no target/root findings"
fi
echo "ok  $n of our blobs: no dangling arc, one root, every fwd/back paired, every node reachable; $sun"
