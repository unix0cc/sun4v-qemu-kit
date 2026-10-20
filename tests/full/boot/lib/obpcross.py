#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""obpcross.py -- what the guest MD says vs what OpenBoot then shows. Used by bootdrv.py.

cross(md_bin, snapshot_text, banner_text) -> (failures, report)
  failures  the checks below that did not hold (the boot test fails on any)
  report    text: EVERY guest-MD property, `+` if OpenBoot was verified to carry it (tree or banner) and `-` if nothing in the tree or
            banner carries it: read by Solaris directly, by nothing, or shown under a name this table does not know

The checks are a table of the mappings OpenBoot is seen to apply on legion, each verified against the snapshot, not assumed:
  /aliases                MD devalias node (every property but `name`, both directions)
  /cpu@0                  MD cpu: clock-frequency, compatible list; device_type cpu
  /memory@m0,<base>       MD mblock: reg = base, size as two 64-bit cells
  /virtual-devices@<cfg>  MD virtual-devices: cfg-handle in the unit address, device-type, compatible (MD list is a prefix)
  <name>@<cfg>            each MD virtual-device child: name, unit address = cfg-handle, device-type, compatible; `interrupts` = intr when intr != 0
                          (measured: disk and rtc show interrupts 1 with intr 0 in the MD, nvram shows none -- OpenBoot's own doing)
  /options                MD `variables` node (every property); the MD `options` node is reported, not required
  banner                  MD platform banner-name is the start of the first line; `Host ID` = hostid; `Ethernet address` = mac-address;
                          `<n> MB memory` = mblock size"""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'md', 'lib'))
import mdparse

class Missing(list):
    pass

class Node(dict):
    """An OpenBoot node. A property it lacks reads as ['<missing>'] (the check then fails, with that in its message) instead of raising
    KeyError and ending the run with a traceback."""
    def __missing__(self, key): return Missing(['<missing>'])

def load_snapshot(text):
    tree = {}; cur = None
    for l in text.split('\n'):
        if l.startswith('## '):
            cur = l[3:]; tree[cur] = Node(); last = None
        elif cur is not None and cur not in ('.version', 'show-devs') and l.strip():
            if l.startswith(' ' * 20) and last is not None: tree[cur][last].append(l.strip())
            else:
                name = l[:25].strip(); tree[cur].setdefault(name, []); tree[cur][name] = [l[25:].strip()] if l[25:].strip() else []; last = name
    return tree

def cells(prop):
    if isinstance(prop, Missing): return [None]
    return [int(x, 16) for x in ' '.join(prop).split()] if prop is not None else None

def cross(md_bin, snapshot_text, banner_text):
    md = mdparse.parse(open(md_bin, 'rb').read()); tree = load_snapshot(snapshot_text)
    fails = []; seen = set()                      # seen: (node name, key) OpenBoot was verified to carry
    def by_name(n): return [x for x in md.values() if x.name == n]
    def one(n):
        r = by_name(n); return r[0] if len(r) == 1 else None
    def need(cond, msg):
        if not cond: fails.append(msg)
    def lst(v):
        s = mdparse.strings(v) if isinstance(v, bytes) else ([v] if isinstance(v, str) else None); return s

    # aliases
    da = one('devalias'); al = tree.get('/aliases')
    if da is None or al is None: fails.append('devalias node or /aliases missing')
    else:
        mdal = {k: v for k, kind, v in da.props}; obal = {k: ' '.join(v) for k, v in al.items() if k != 'name'}
        need(mdal == obal, '/aliases differ from the MD devalias node: MD %s, OpenBoot %s' % (mdal, obal))
        seen |= {('devalias', k) for k in mdal}
    # cpu
    cpu = one('cpu'); oc = tree.get('/cpu@0')
    if cpu is None or oc is None: fails.append('cpu node or /cpu@0 missing')
    else:
        need(cells(oc['clock-frequency'])[0] == cpu.get('clock-frequency'), '/cpu@0 clock-frequency %s != MD %#x' % (oc['clock-frequency'], cpu.get('clock-frequency')))
        need(oc['compatible'] == lst(cpu.get('compatible')), '/cpu@0 compatible %s != MD %s' % (oc['compatible'], lst(cpu.get('compatible'))))
        need(oc['device_type'] == ['cpu'] and oc['name'] == ['cpu'], '/cpu@0 device_type/name are not cpu')
        seen |= {('cpu', 'clock-frequency'), ('cpu', 'compatible')}
    # memory
    mb = one('mblock')
    if mb is None: fails.append('mblock node missing')
    else:
        base, size = mb.get('base'), mb.get('size'); path = '/memory@m0,%x' % base; om = tree.get(path)
        if om is None: fails.append('no %s in the tree for MD mblock base %#x' % (path, base))
        else:
            want = [base >> 32, base & 0xffffffff, size >> 32, size & 0xffffffff]
            need(cells(om['reg']) == want, '%s reg %s != MD base/size %s' % (path, om['reg'], [hex(x) for x in want]))
            seen |= {('mblock', 'base'), ('mblock', 'size')}
    # virtual-devices and children
    vd = one('virtual-devices')
    if vd is None: fails.append('virtual-devices node missing')
    else:
        vpath = '/virtual-devices@%x' % vd.get('cfg-handle'); ov = tree.get(vpath)
        if ov is None: fails.append('no %s in the tree' % vpath)
        else:
            need(ov['device_type'] == [vd.get('device-type')], '%s device_type %s != MD %s' % (vpath, ov['device_type'], vd.get('device-type')))
            m = lst(vd.get('compatible')); need(ov['compatible'][:len(m)] == m, '%s compatible %s does not start with MD %s' % (vpath, ov['compatible'], m))
            seen |= {('virtual-devices', 'cfg-handle'), ('virtual-devices', 'device-type'), ('virtual-devices', 'compatible')}
            for ci in vd.fwd:
                ch = md[ci]
                if ch.name != 'virtual-device': continue
                nm = ch.get('name'); cpath = '%s/%s@%x' % (vpath, nm, ch.get('cfg-handle')); oc2 = tree.get(cpath)
                if oc2 is None: fails.append('no %s in the tree for MD virtual-device %s cfg-handle %#x' % (cpath, nm, ch.get('cfg-handle'))); continue
                need(oc2['name'] == [nm], '%s name %s != %s' % (cpath, oc2['name'], nm))
                seen |= {(nm, 'name'), (nm, 'cfg-handle')}
                if ch.get('device-type') is not None:
                    need(oc2['device_type'] == [ch.get('device-type')], '%s device_type %s != MD %s' % (cpath, oc2['device_type'], ch.get('device-type'))); seen.add((nm, 'device-type'))
                cm = lst(ch.get('compatible'))
                if cm is not None:
                    need(oc2['compatible'][:len(cm)] == cm, '%s compatible %s does not start with MD %s' % (cpath, oc2['compatible'], cm)); seen.add((nm, 'compatible'))
                if ch.get('intr') not in (None, 0):          # OpenBoot supplies its own `interrupts` for disk and rtc where the MD says intr 0
                    need(cells(oc2['interrupts']) == [ch.get('intr')], '%s interrupts %s != MD intr %s' % (cpath, oc2['interrupts'], ch.get('intr'))); seen.add((nm, 'intr'))
    # options
    va = one('variables'); oo = tree.get('/options')
    if va is None or oo is None: fails.append('variables node or /options missing')
    else:
        for k, kind, v in va.props:
            need(oo.get(k) == [v], '/options %s is %s, MD variables says %r' % (k, oo.get(k), v)); seen.add(('variables', k))
    # banner
    pl = one('platform'); first = next((l for l in banner_text.split('\n') if 'Sun Fire' in l), '')
    if pl is None: fails.append('platform node missing')
    else:
        need(first.startswith(pl.get('banner-name')), 'banner line %r does not start with MD banner-name %r' % (first, pl.get('banner-name')))
        m = re.search(r'Host ID: ([0-9a-f]+)', banner_text); need(m and int(m.group(1), 16) == pl.get('hostid'), 'Host ID %s != MD hostid %#x' % (m and m.group(1), pl.get('hostid')))
        m = re.search(r'Ethernet address ([0-9a-f:]+)', banner_text)
        mac = pl.get('mac-address'); want = ':'.join('%x' % ((mac >> s) & 0xff) for s in range(40, -8, -8))
        need(m and m.group(1) == want, 'Ethernet address %s != MD mac-address %s' % (m and m.group(1), want))
        m = re.search(r'(\d+) MB memory', banner_text); need(m and mb and int(m.group(1)) == mb.get('size') >> 20, '%s MB memory != MD mblock size' % (m and m.group(1)))
        seen |= {('platform', 'banner-name'), ('platform', 'hostid'), ('platform', 'mac-address')}
    # report: everything else in the guest MD
    blob = snapshot_text + '\n' + banner_text
    lines = []
    for n in sorted(md.values(), key=lambda x: x.idx):
        label = n.get('name') if n.name == 'virtual-device' and n.get('name') else n.name
        for k, kind, v in n.props:
            shown = (label, k) in seen or (n.name, k) in seen
            s2 = mdparse.strings(v) if kind == 'd' else None
            val = ('%r' % s2 if s2 else ('0x%x' % v if kind == 'v' else repr(v) if kind == 's' else v.hex()))
            found = ''
            if not shown:
                if kind == 'v' and v >= 0x1000 and ('%08x' % v in blob): found = '   [the value appears in the tree]'
                if kind == 's' and len(v) >= 4 and v in blob: found = '   [the value appears in the tree]'
            lines.append('%s %-24s %-22s %s%s' % ('+' if shown else '-', n.name + ('(' + n.get('name') + ')' if label != n.name else ''), k, val[:70], found))
    return fails, '\n'.join(lines) + '\n'
