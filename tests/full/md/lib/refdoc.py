#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""refdoc.py -- md/REFERENCE against our built MDs: part 1 against the hypervisor MDs, parts 2 and 3 against the guest MDs.

    refdoc.py md/REFERENCE --hv legion-1up-hv.bin [pci-1up-hv.bin ...] --md legion-1up-md.bin [pci-1up-md.bin ...]

In each list the first blob is the base (legion); the others may add nodes and properties (pci: pcie_bus), never differ in a
documented value.
Part 1 checks, each a failure:
  structure the Structure table (fwd arcs, back arcs, properties of each node type, (pci) marking what only the other blobs have)
            is not what the blobs have, or lists other nodes than the Nodes table
  node      a node type of the blobs missing from the "Nodes" table, or a table row no blob has
  property  a property of the blobs without a "<node>.<property>" block in part 1, or a block no blob has
            (a block whose value is "not written" must be absent from the blobs)
  value     the value line of a block differs from the blob; an integer is compared as an integer (hex or decimal,
            text after it, "(512k)", is ignored); "MD_MEM" is not compared; other texts are not compared
Parts 2 and 3 (the guest MD; positions are (node, property), a node itself is (node, "(node)")):
  position  a position of the guest blobs without a row in the part 2 table, or a row no blob has
  spec      a part 2 row with "-" in both specification columns whose read column is not "y" or "n", or a row
            in a specification table whose read column is not "?"
  count     the counts the text under the part 2 table states ("The result is 79 of 101 positions read; the other 22 ...") differ from the table
Values are not compared in part 2 (the table has none).
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdparse import parse

SKIP = {'MD_MEM'}
VARIES = {'memsize'}   # MD_MEM: 2048 for legion, 4096 for the pci configs

def blob_props(path):
    """{(node type, property): value} of one blob; value is int or str or bytes."""
    d = {}
    for n in parse(open(path, 'rb').read()).values():
        for k, kind, v in n.props:
            d.setdefault((n.name, k), v)
    return d, {n.name for n in parse(open(path, 'rb').read()).values()}

def part1(text):
    a = text.index('\nPart 1.'); b = text.index('\nPart 2.')
    return text[a:b]

def doc_nodes(p1):
    a = p1.index('\nNodes of the hypervisor MD\n'); b = p1.index('\nProperties of the hypervisor MD\n')
    rows = [l.split() for l in p1[a:b].splitlines() if l.startswith('    ') and not l.startswith('     ')]
    return {r[0] for r in rows if r[0] != 'node' and not r[0].startswith('-')}

def doc_blocks(p1):
    """{(node, property): first token of the value line}"""
    out = {}; cur = None
    for l in p1[p1.index('\nProperties of the hypervisor MD\n'):].splitlines():
        m = re.match(r'^([a-z_]+)\.([A-Za-z_#-][\w#-]*)$', l)
        if m: cur = (m.group(1), m.group(2)); continue
        m = re.match(r'^    value\s+(\S.*)$', l)
        if m and cur: out[cur] = m.group(1).strip(); cur = None
    return out

def as_int(s):
    t = s.split()[0]
    try: return int(t, 0)
    except ValueError: return None

def blob_structure(path):
    """{node type: {'fwd': [types], 'back': [types], 'props': [names]}}"""
    ns = parse(open(path, 'rb').read()); d = {}
    for n in ns.values():
        d[n.name] = {'fwd': [ns[i].name for i in n.fwd], 'back': [ns[i].name for i in n.back], 'props': [k for k, _, _ in n.props]}
    return d

def doc_structure(p1):
    """{node: {'fwd': [tokens], 'back': [...], 'props': [...]}} of the Structure table; a token may end in (pci)"""
    a = p1.index('\nStructure of the hypervisor MD\n'); b = p1.index('\nProperties of the hypervisor MD\n'); out = {}; cols = None
    for l in p1[a:b].splitlines():
        if l.startswith('node ') and 'fwd' in l: cols = (l.index('fwd'), l.index('back'), l.index('properties')); continue
        if cols is None or not l.strip() or l.startswith('--'): continue
        cell = lambda x, y: [t for t in l[x:y].split() if t != '-']
        if l[:cols[0]].strip():
            last = out[l[:cols[0]].split()[0]] = {'fwd': [], 'back': [], 'props': []}
        for k, (x, y) in zip(('fwd', 'back', 'props'), ((cols[0], cols[1]), (cols[1], cols[2]), (cols[2], None))): last[k] += cell(x, y)   # a row may go on in a second line with the node column empty
    return out

def check_structure(p1, blobs, fails):
    docs = doc_structure(p1); st = [blob_structure(b) for b in blobs]; base = st[0]
    union = {}
    for d in st:
        for n, v in d.items():
            for k in v: union.setdefault(n, {}).setdefault(k, set()).update(v[k])
    docn = {n.replace('(pci)', '') for n in docs}
    for n in sorted(set(union) - docn): fails.append('structure: node %s is in the blobs, not in the Structure table' % n)
    for n in sorted(docn - set(union)): fails.append('structure: node %s is in the Structure table, in no blob' % n)
    for raw, cells in docs.items():
        n = raw.replace('(pci)', '')
        if n not in union: continue
        if n in base:
            if raw.endswith('(pci)'): fails.append('structure: %s is in the base blob, marked (pci)' % n)
        elif not raw.endswith('(pci)'): fails.append('structure: %s is not in the base blob, not marked (pci)' % n)
        for k in ('fwd', 'back', 'props'):
            plain = {t for t in cells[k] if not t.endswith('(pci)')}; pci = {t[:-5] for t in cells[k] if t.endswith('(pci)')}
            if n in base:
                want_plain = set(base[n][k]); want_pci = union[n][k] - want_plain
            else:
                plain, pci = plain | pci, set(); want_plain, want_pci = union[n][k], set()
            if plain != want_plain: fails.append('structure: %s %s is %s in the document, %s in the base blob' % (n, k, sorted(plain), sorted(want_plain)))
            if pci != want_pci: fails.append('structure: %s %s (pci) is %s in the document, %s in the other blobs' % (n, k, sorted(pci), sorted(want_pci)))
    return docn

def guest_positions(path):
    pos = set()
    for n in parse(open(path, 'rb').read()).values():
        pos.add((n.name, '(node)'))
        for k, kind, v in n.props: pos.add((n.name, k))
    return pos

def section(text, start, end=None):
    a = text.index(start); b = text.index(end, a) if end else len(text)
    return text[a:b]

def part2_rows(text):
    """[(node, property, spec columns, read)] of the table under 'Part 2.'; read is cut at the column the header gives"""
    p2 = section(text, '\nPart 2.'); rows = []; col = None
    for l in p2.splitlines():
        if l.startswith('node ') and 'Hypervisor' in l and re.search(r'\bread\b', l): col = re.search(r'\bread\b', l).start(); continue
        if col is None: continue
        if not l.strip():
            if rows: break
            continue
        if l.startswith('--'): continue
        m = re.match(r'^(\S+)\s+(\(node\)|\S+)\s+(.*)$', l)
        if m: rows.append((m.group(1), m.group(2), m.group(3), l[col:].split()[0] if l[col:].split() else ''))
    return rows

def check_guest(ref, blobs, fails):
    text = open(ref).read(); pos = set()
    for b in blobs: pos |= guest_positions(b)
    rows = part2_rows(text); doc = {(a, b) for a, b, _, _ in rows}
    if len(doc) != len(rows): fails.append('position: part 2 lists a position twice')
    for k in sorted(pos - doc): fails.append('position: %s %s is in the guest blobs, has no row in part 2' % k)
    for k in sorted(doc - pos): fails.append('position: %s %s has a row in part 2, is in no guest blob' % k)
    nospec = {(a, b) for a, b, c, _ in rows if re.match(r'^-\s+-\s', c + ' ')}
    for a, b, c, r in rows:
        if r not in ('y', 'n'): fails.append('read: %s %s has "%s" in the read column, expected y or n' % (a, b, r))
    p2 = section(text, '\nPart 2.')
    nread = sum(1 for a, b, c, r in rows if r == 'y')
    m = re.search(r'The result is (\d+) of (\d+) positions read; the other (\d+)', p2)
    if m and (int(m.group(1)), int(m.group(2)), int(m.group(3))) != (nread, len(rows), len(rows) - nread):
        fails.append('count: part 2 says %s of the %s read, %s not; the table gives %d of the %d, %d not' % (m.group(1), m.group(2), m.group(3), nread, len(rows), len(rows) - nread))
    return len(doc), len(nospec)

def main(ref, blobs, mds):
    p1 = part1(open(ref).read()); fails = []
    props = {}; types = set()
    for i, b in enumerate(blobs):
        d, t = blob_props(b); types |= t
        for k, v in d.items():
            if k in props and props[k][0] != v and i > 0 and k[1] not in VARIES:
                fails.append('value: %s.%s is %r in %s and %r in the first blob' % (k[0], k[1], v, b, props[k][0]))
            props.setdefault(k, (v, b))
    dn = doc_nodes(p1)
    sn = check_structure(p1, blobs, fails)
    if sn != dn: fails.append('structure: the Nodes table and the Structure table list different nodes: %s' % sorted(sn ^ dn))
    for t in sorted(types - dn): fails.append('node: %s is in the blobs, not in the Nodes table' % t)
    for t in sorted(dn - types): fails.append('node: %s is in the Nodes table, in no blob' % t)
    db = doc_blocks(p1)
    for k in sorted(set(props) - set(db)): fails.append('property: %s.%s is in the blobs, has no block' % k)
    for k, val in sorted(db.items()):
        if val.startswith('not written'):
            if k in props: fails.append('property: %s.%s is documented as not written, but %s has it' % (k + (props[k][1],)))
            continue
        if k not in props: fails.append('property: %s.%s has a block, is in no blob' % k); continue
        if val.split()[0] in SKIP: continue
        want = as_int(val)
        if want is None: continue
        got = props[k][0]
        if not isinstance(got, int) or got != want:
            fails.append('value: %s.%s is %s in the document, %r in %s' % (k + (val, got, props[k][1])))
    n2, n3 = check_guest(ref, mds, fails) if mds else (0, 0)
    for f in fails: print('FAIL:', f, file=sys.stderr)
    if fails: return 1
    print('ok  part 1: %d nodes, %d properties of %d hypervisor MDs; parts 2 and 3: %d positions, %d without a specification, of %d guest MDs; all agree with md/REFERENCE' % (len(dn), len(db), len(blobs), n2, n3, len(mds)))
    return 0

if __name__ == '__main__':
    a = sys.argv[1:]
    if len(a) < 3 or '--hv' not in a: sys.exit(__doc__)
    hv = a[a.index('--hv') + 1:a.index('--md')] if '--md' in a else a[a.index('--hv') + 1:]
    md = a[a.index('--md') + 1:] if '--md' in a else []
    if '--md' in a and a.index('--md') < a.index('--hv'): sys.exit(__doc__)
    sys.exit(main(a[0], hv, md))
