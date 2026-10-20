#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""mdgraph.py <md.bin> [--plain] -- check the graph an MD encodes; print one line per finding, exit 1 if any.

mdlint checks only the node/end element sequence (it passes an arc pointing at a node that does not
exist). This checks the graph:
  target   every arc points at the index of a node element ('N'), not into a property or past the end
  pair     every `fwd` from A to B has a `back` from B to A, and every `back` from A to B a `fwd` from B to A
  reach    every node is reachable from the node named `root` along fwd arcs (the root is not the first
           element: our guest MD declares an mblock first)
  root     there is exactly one node named `root`
Arc names other than fwd/back are reported as 'other' (counted, not an error).

Only `target` and `root` are laws of the format. `pair` and `reach` are NOT: Sun's own shipped 1up-md.bin has a
root fwd -> platform with no back arc and options/devalias nodes the root cannot reach by fwd arcs. For our own
blobs tests/full/md fails on any finding; for Sun's shipped binaries it checks `target` and `root` only."""
import struct, sys, collections

def load(path):
    b = open(path, 'rb').read()
    ver, nsz, namesz, datasz = struct.unpack_from('>IIII', b, 0)
    nodes = b[16:16 + nsz]; names = b[16 + nsz:16 + nsz + namesz]
    els = []
    for i in range(nsz // 16):
        tag, nlen, _r, noff = struct.unpack_from('>BBHI', nodes, i * 16)
        raw = nodes[i * 16 + 8:i * 16 + 16]
        name = names[noff:names.index(b'\0', noff)].decode('latin1') if chr(tag) in 'Nvasd' and noff < len(names) else ''
        els.append((chr(tag), name, raw))
    return els

PLAIN = '--plain' in sys.argv     # names without element indexes, so a baseline survives unrelated MD edits

def check(els):
    out = []
    n = len(els)
    # owner node of every element
    owner = {}; cur = None
    nodeidx = []
    for i, (t, nm, raw) in enumerate(els):
        if t == 'N': cur = i; nodeidx.append(i)
        elif t == 'E': cur = None
        owner[i] = cur
    label = lambda i: els[i][1] if PLAIN else '%s@%d' % (els[i][1], i)
    arcs = collections.defaultdict(set)     # (kind) -> {(from,to)}
    other = collections.Counter()
    for i, (t, nm, raw) in enumerate(els):
        if t != 'a': continue
        tgt = struct.unpack('>Q', raw)[0]
        src = owner[i]
        if src is None:
            out.append('owner: arc %s at element %d is not inside any node' % (nm, i))
            continue
        if tgt >= n or els[tgt][0] != 'N':
            out.append('target: %s -> %s arc to element %d which is %s' % (label(src), nm, tgt,
                       'past the end' if tgt >= n else 'not a node (%r)' % els[tgt][0]))
            continue
        if nm in ('fwd', 'back'): arcs[nm].add((src, tgt))
        else: other[nm] += 1
    for a, b in sorted(arcs['fwd']):
        if (b, a) not in arcs['back']: out.append('pair: %s fwd -> %s has no back arc' % (label(a), label(b)))
    for a, b in sorted(arcs['back']):
        if (b, a) not in arcs['fwd']: out.append('pair: %s back -> %s has no fwd arc' % (label(a), label(b)))
    roots = [i for i in nodeidx if els[i][1] == 'root']
    if len(roots) != 1: out.append('root: %d nodes named root, want exactly 1' % len(roots))
    seen = set(roots); todo = list(seen)
    fw = collections.defaultdict(list)
    for a, b in arcs['fwd']: fw[a].append(b)
    while todo:
        for b in fw[todo.pop()]:
            if b not in seen: seen.add(b); todo.append(b)
    for i in nodeidx:
        if i not in seen: out.append('reach: %s is not reachable from the root by fwd arcs' % label(i))
    return out, other

if __name__ == '__main__':
    findings, other = check(load(sys.argv[1]))
    for f in findings: print(f)
    if other: print('note: other arc names: %s' % dict(other), file=sys.stderr)
    sys.exit(1 if findings else 0)
