#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""mdparse.py -- read a binary MD into Python objects (for the tests; mdunfold.py is the text form).

    nodes = parse(open(p,'rb').read())     # {element index: Node}
    Node: .idx .name .props [(key, kind, value)] .fwd [idx] .back [idx]     kind is 'v' int, 's' str, 'd' bytes
    strings(value)  a data property that is NUL-separated printable strings -> ['a','b'] (or None if it is not)"""
import struct

class Node:
    def __init__(self, idx, name): self.idx, self.name, self.props, self.fwd, self.back = idx, name, [], [], []
    def get(self, key, default=None):
        for k, kind, v in self.props:
            if k == key: return v
        return default
    def __repr__(self): return 'Node(%s@%d)' % (self.name, self.idx)

def parse(b):
    ver, nsz, namesz, datasz = struct.unpack_from('>IIII', b, 0)
    nodes_b = b[16:16 + nsz]; names = b[16 + nsz:16 + nsz + namesz]; data = b[16 + nsz + namesz:]
    cstr = lambda blk, off: blk[off:blk.index(b'\0', off)].decode('latin1')
    out = {}; cur = None
    for i in range(nsz // 16):
        tag, nlen, _r, noff = struct.unpack_from('>BBHI', nodes_b, i * 16); raw = nodes_b[i * 16 + 8:i * 16 + 16]; t = chr(tag)
        if t == 'N': cur = Node(i, cstr(names, noff)); out[i] = cur
        elif t == 'E': cur = None
        elif cur is None: continue
        elif t == 'v': cur.props.append((cstr(names, noff), 'v', struct.unpack('>Q', raw)[0]))
        elif t == 's':
            dl, do = struct.unpack('>II', raw); cur.props.append((cstr(names, noff), 's', data[do:do + dl - 1].decode('latin1')))
        elif t == 'd':
            dl, do = struct.unpack('>II', raw); cur.props.append((cstr(names, noff), 'd', bytes(data[do:do + dl])))
        elif t == 'a':
            nm = cstr(names, noff); tgt = struct.unpack('>Q', raw)[0]
            if nm == 'fwd': cur.fwd.append(tgt)
            elif nm == 'back': cur.back.append(tgt)
    return out

def strings(v):
    if not isinstance(v, bytes) or not v or v[-1:] != b'\0': return None
    parts = v[:-1].split(b'\0')
    return [p.decode('latin1') for p in parts] if all(p and all(32 <= c < 127 for c in p) for p in parts) else None
