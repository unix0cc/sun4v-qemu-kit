#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""mdunfold.py <md.bin> -- unfold a binary MD into mdgen source, one element per line, no cpp, no macros.

Refolding it with mdgen must give the same bytes:  mdgen --binary --outfile out.bin <this output>.
Nodes are labelled n<element-index>; property order, arc order and node order are the binary's own,
so the text is a canonical form: build(unfold(B)) == B and unfold(build(unfold(B))) == unfold(B).
Data properties are written byte by byte (mdgen drops leading zero bytes of a wider number, so a
byte is the only spelling that keeps the length)."""
import struct, sys

def cstr(blk, off):
    return blk[off:blk.index(b'\0', off)].decode('latin1')

def unfold(b):
    ver, nsz, namesz, datasz = struct.unpack_from('>IIII', b, 0)
    if ver != 0x10000 or len(b) != 16 + nsz + namesz + datasz:
        raise SystemExit('not an MDESC: version %#x, size %d vs %d' % (ver, len(b), 16 + nsz + namesz + datasz))
    nodes = b[16:16 + nsz]; names = b[16 + nsz:16 + nsz + namesz]; data = b[16 + nsz + namesz:]
    n = nsz // 16
    out = []
    depth = 0
    for i in range(n):
        tag, nlen, _r, noff = struct.unpack_from('>BBHI', nodes, i * 16)
        raw = nodes[i * 16 + 8:i * 16 + 16]
        t = chr(tag)
        name = cstr(names, noff) if t != 'E' and t != '\0' else ''
        if t == 'N':
            out.append('node %s n%d {' % (name, i)); depth = 1
        elif t == 'E':
            out.append('}\n'); depth = 0
        elif t == 'v':
            out.append('\t%s = 0x%x;' % (name, struct.unpack('>Q', raw)[0]))
        elif t == 'a':
            out.append('\t%s -> n%d;' % (name, struct.unpack('>Q', raw)[0]))
        elif t == 's':
            dl, do = struct.unpack('>II', raw)
            s = data[do:do + dl - 1].decode('latin1')
            out.append('\t%s = "%s";' % (name, s.replace('\\', '\\\\').replace('"', '\\"')))
        elif t == 'd':
            dl, do = struct.unpack('>II', raw)
            out.append('\t%s = { %s };' % (name, ', '.join('0x%02x' % c for c in data[do:do + dl])))
        elif t == '\0':
            if i != n - 1: raise SystemExit('element %d: terminator not last' % i)
        else:
            raise SystemExit('element %d: unknown tag %r' % (i, t))
    return '\n'.join(out) + '\n'

if __name__ == '__main__':
    sys.stdout.write(unfold(open(sys.argv[1], 'rb').read()))
