#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""bootdrv.py -- boot a firmware set under QEMU to the OpenBoot `ok` prompt and read the device tree.

    bootdrv.py --name legion --outdir DIR --fw FWDIR --expect-banner 'legion, 4096MB' --snapshot expected/legion.obp
               [--update] [--attempts 3] [--timeout 240] -- <qemu binary> <qemu args ...>

The console is a unix socket (-serial unix:...), read without blocking, every wait has a timeout, and on failure the last
console lines are printed. Steps: wait for `ok`; the first banner line must contain --expect-banner; `.version`; `show-devs`;
`dev <path> .properties` for every device; the resulting text (volatile parts normalised) must equal the --snapshot file, or is
written to it with --update; the firmware files QEMU loaded must all come from --fw (a stray openboot.bin in the cwd or another -L directory beats -L silently, hence the trace check).

Exit: 0 pass, 1 the content is wrong (never retried), 2 no prompt / QEMU died (a flake or a dead hv; retried up to --attempts).
The attempt count is printed: a pass on the 2nd attempt is a pass with a warning, because OBP has a known ~1/10 loader flake."""
import argparse, os, re, shutil, socket, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import obpcross

ap = argparse.ArgumentParser()
ap.add_argument('--name', required=True); ap.add_argument('--outdir', required=True); ap.add_argument('--fw', required=True)
ap.add_argument('--expect-banner', required=True); ap.add_argument('--snapshot', required=True)
ap.add_argument('--surface', help='file listing every guest-MD property with + (OpenBoot shows it) or - (it does not); drift is a warning')
ap.add_argument('--update', action='store_true'); ap.add_argument('--attempts', type=int, default=3)
ap.add_argument('--timeout', type=int, default=240)
ap.add_argument('qemu', nargs=argparse.REMAINDER)
a = ap.parse_args()
qemu = [x for x in a.qemu if x != '--']
os.makedirs(a.outdir, exist_ok=True)
FILES = ['reset.bin', 'q.bin', 'openboot.bin', 'nvram1', '1up-md.bin', '1up-hv.bin']

class Console:
    def __init__(self, path, timeout):
        self.buf = b''; self.s = None
        end = time.time() + 30
        while time.time() < end:
            try:
                s = socket.socket(socket.AF_UNIX); s.connect(path); s.setblocking(False); self.s = s; return
            except OSError: time.sleep(0.2)
        raise RuntimeError('console socket never appeared')
    def read(self, secs):
        import select
        r, _, _ = select.select([self.s], [], [], secs)
        if r:
            d = self.s.recv(65536)
            if not d: raise EOFError('console closed')
            self.buf += d
    def wait_ok(self, timeout, since):
        end = time.time() + timeout
        pat = re.compile(rb'(^|\n)ok $')
        while time.time() < end:
            self.read(1.0)
            if pat.search(self.buf[since:].replace(b'\r', b'')): return True
        return False
    def send(self, t): self.s.sendall(t.encode())
    def text(self): return self.buf.decode('latin1').replace('\r', '')

def norm(t, path=''):
    """The parts of the OpenBoot output that change with the commit or the run, not with the machine."""
    t = re.sub(r'(4\.x\.build_122\+qemu)-[0-9A-Za-z._+]+', r'\1', t)               # a tagged commit (build/stamp.sh) appends the release: 4.x.build_122+qemu-0.1
    t = re.sub(r'\[ sun4v-qemu-kit [^\]]*\]', '[ sun4v-qemu-kit <stamp> ]', t)
    t = re.sub(r'(OBP \S+) \d{4}/\d\d/\d\d \d\d:\d\d', r'\1 <date>', t)          # /openprom version: the build time (commit date when the tree is clean)
    t = re.sub(r'created \d{4}/\d\d/\d\d \d\d:\d\d', 'created <date>', t)
    if path == '/memory@m0,80000000':                    # the free list depends on what OBP has allocated so far
        t = '\n'.join(l for l in t.split('\n') if not l.startswith('available'))
    return t

def attempt(n):
    tmp = tempfile.mkdtemp(prefix='bootdrv-')          # neutral cwd: a stray firmware file here must not matter
    sock = os.path.join(tmp, 'con.sock'); log = os.path.join(a.outdir, '%s.qemu.log' % a.name)
    cmd = qemu + ['-display', 'none', '-monitor', 'none', '-serial', 'unix:%s,server=on,wait=off' % sock,
                  '-d', 'guest_errors,unimp', '-D', log, '-trace', 'load_file']
    # stderr goes to a file, not a pipe nobody reads: a QEMU that writes more than the pipe holds (64 KB) would stop on it
    errf = os.path.join(a.outdir, '%s.qemu.stderr' % a.name)
    with open(errf, 'wb') as ef:
        p = subprocess.Popen(cmd, cwd=tmp, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=ef)
    t0 = time.time(); c = None
    try:
        c = Console(sock, 30)
        if not c.wait_ok(a.timeout, 0):
            return 2, 'no ok prompt within %ds' % a.timeout, c
        banner_text = c.text()
        first = next((l for l in c.text().split('\n') if 'Sun Fire' in l or 'SUNW' in l), '')
        if a.expect_banner not in first:
            return 1, 'banner line %r lacks %r' % (first, a.expect_banner), c
        def ask(cmd, tmo=90):
            """Send a command, answer OpenBoot's pager (`More [<space>,<cr>,q,n,p,c] ?`) with a space, return the output
            without the echo, the pager and the prompt."""
            before = len(c.buf); c.send(cmd + '\n'); end = time.time() + tmo; pos = before
            while True:
                if time.time() > end: raise RuntimeError('no ok after %r' % cmd)
                c.read(0.5)
                tail = c.buf[pos:]
                if b'More [<space>' in tail:
                    c.send(' '); pos = len(c.buf); continue
                if re.search(rb'(^|\n)ok $', c.buf[before:].replace(b'\r', b'')): break
            out = re.sub(r'\x1b\[[0-9;]*m', '', c.buf[before:].decode('latin1').replace('\r', ''))
            # the pager prompt can share a line with the next output line: cut the prompt out, keep the rest
            lines = [re.sub(r'.*More \[<space>[^\]]*\] \?\s*', '', l) if 'More [<space>' in l else l for l in out.split('\n')[1:]]
            lines = [l for l in lines if l.strip()]
            body = '\n'.join(l.rstrip() for l in lines if l.strip() != 'ok' and not l.startswith('ok '))
            return body
        ver = ask('.version')
        devs = sorted({l.strip() for l in ask('show-devs').split('\n') if l.startswith('/')})
        if not devs: return 1, 'show-devs printed no device paths', c
        snap = ['## .version', norm(ver), '', '## show-devs'] + devs
        for d in devs:
            snap += ['', '## ' + d, norm(ask('dev %s .properties' % d), d)]
        text = '\n'.join(snap) + '\n'
        fails, report = obpcross.cross(os.path.join(a.fw, '1up-md.bin'), text, banner_text)
        open(os.path.join(a.outdir, a.name + '.surface'), 'w').write(report)
        if fails: return 1, 'the MD and what OpenBoot shows disagree:\n  ' + '\n  '.join(fails), c
        if a.surface and not a.update and os.path.exists(a.surface) and open(a.surface).read() != report:
            print('WARNING %s: which guest-MD properties OpenBoot shows changed; see %s vs %s' % (a.name, a.surface, os.path.join(a.outdir, a.name + '.surface')), file=sys.stderr)
        if a.surface and a.update: open(a.surface, 'w').write(report)
        # firmware provenance: every loaded file comes from --fw
        loaded = {}
        for l in open(log, errors='replace'):
            m = re.match(r'load_file name (\S+) location (\S+)', l)
            if m: loaded[os.path.basename(m.group(1))] = m.group(2)
        bad = [f for f in FILES if f in loaded and os.path.dirname(loaded[f]) != os.path.abspath(a.fw)]
        missing = [f for f in ('1up-md.bin', '1up-hv.bin', 'q.bin', 'reset.bin', 'openboot.bin') if f not in loaded]
        if bad or missing: return 1, 'firmware not from %s: %s missing: %s' % (a.fw, {f: loaded[f] for f in bad}, missing), c
        if a.update:
            open(a.snapshot, 'w').write(text); return 0, 'wrote %s (%d devices, %d lines)' % (a.snapshot, len(devs), text.count('\n')), c
        want = open(a.snapshot).read()
        if text != want:
            import difflib
            d = list(difflib.unified_diff(want.split('\n'), text.split('\n'), 'expected', 'got', lineterm='', n=1))
            return 1, 'OpenBoot tree differs (%d diff lines):\n%s' % (len(d), '\n'.join(d[:80])), c
        return 0, '%d devices, %d lines match, banner ok, firmware from %s, %ds' % (len(devs), text.count('\n'), a.fw, time.time() - t0), c
    except (EOFError, RuntimeError) as e:
        return 2, 'QEMU/console: %s; stderr: %s' % (e, open(errf, 'rb').read()[-2000:].decode('latin1')), c
    finally:
        p.terminate()
        try: p.wait(10)
        except Exception: p.kill()
        shutil.rmtree(tmp, ignore_errors=True)

rc = 2
for n in range(1, a.attempts + 1):
    rc, msg, c = attempt(n)
    if c: open(os.path.join(a.outdir, '%s.console' % a.name), 'w').write(c.text())
    if rc == 0:
        print('ok  %-13s %s%s' % (a.name, msg, '' if n == 1 else '   WARNING: passed on attempt %d of %d' % (n, a.attempts)))
        sys.exit(0)
    print('%s %-13s attempt %d/%d: %s' % ('FAIL' if rc == 1 else 'try ', a.name, n, a.attempts, msg), file=sys.stderr)
    if rc == 1: break
    if c: print('    last console lines:\n' + '\n'.join('      ' + l for l in c.text().split('\n')[-8:]), file=sys.stderr)
sys.exit(rc)
