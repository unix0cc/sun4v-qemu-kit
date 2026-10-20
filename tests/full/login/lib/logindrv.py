#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
"""logindrv.py -- boot a legion firmware set under QEMU, type `boot disk` at the OpenBoot prompt and wait for Solaris's login prompt.

    logindrv.py --name legion --outdir DIR --fw FWDIR [--attempts 3] [--t-ok 120] [--t-login 300] [--t-stall 240]
                [--boot-cmd 'boot disk'] -- <qemu binary> <qemu args ...>

The console is a unix socket (-serial unix:...), read without blocking; every wait has a timeout. After `ok`, the boot command is
typed and the console is classified by the EARLIEST of these markers:
    LOGIN     `console login:`                     pass
    PANIC     `panic[cpuN]`                        fail, the first panic line is printed (never retried)
    OBP-L14   `Last Trap: Level 14`                OpenBoot's loader flake: retried
    OBP-TRAP  any other `ERROR: Last Trap:`        fail
    RETURNED  the OpenBoot prompt came back        the boot command failed (no disk, no kernel): fail
    STALL     nothing new on the console for --t-stall seconds, or --t-login in total: fail
It also checks that QEMU loaded all six firmware files from --fw (a stray blob in the cwd or another -L directory beats -L silently).

Exit: 0 login seen; 1 the guest did not reach login (panic, trap, boot failed, stall); 2 no `ok` prompt / QEMU died / the Level 14
flake after all attempts. A pass on a later attempt is reported with a warning."""
import argparse, os, re, select, socket, subprocess, sys, tempfile, time

ap = argparse.ArgumentParser()
ap.add_argument('--name', required=True); ap.add_argument('--outdir', required=True); ap.add_argument('--fw', required=True)
ap.add_argument('--attempts', type=int, default=3); ap.add_argument('--t-ok', type=int, default=120)
ap.add_argument('--t-login', type=int, default=300); ap.add_argument('--t-stall', type=int, default=240)
ap.add_argument('--boot-cmd', default='boot disk')
ap.add_argument('qemu', nargs=argparse.REMAINDER)
a = ap.parse_args()
qemu = [x for x in a.qemu if x != '--']
os.makedirs(a.outdir, exist_ok=True)
FILES = ['reset.bin', 'q.bin', 'openboot.bin', 'nvram1', '1up-md.bin', '1up-hv.bin']
RE_OK = re.compile(r'(^|\n)ok $')
MARKERS = [('LOGIN', re.compile(r'console login:')), ('PANIC', re.compile(r'panic\[cpu[0-9]+\]')),
           ('OBP-L14', re.compile(r'Last Trap: Level 14')), ('OBP-TRAP', re.compile(r'ERROR: Last Trap:')),
           ('OBP-RED', re.compile(r'Red State Exception|Watchdog Reset'))]

class Console:
    def __init__(self, path):
        self.buf = b''; self.s = None; end = time.time() + 30
        while time.time() < end:
            try:
                s = socket.socket(socket.AF_UNIX); s.connect(path); s.setblocking(False); self.s = s; return
            except OSError: time.sleep(0.2)
        raise RuntimeError('console socket never appeared')
    def read(self, secs):
        r, _, _ = select.select([self.s], [], [], secs)
        if r:
            d = self.s.recv(65536)
            if not d: raise EOFError('console closed')
            self.buf += d; return len(d)
        return 0
    def send(self, t): self.s.sendall(t.encode())
    def text(self, since=0): return self.buf[since:].decode('latin1').replace('\r', '')

def earliest(text):
    best = None
    for name, rx in MARKERS:
        m = rx.search(text)
        if m and (best is None or m.start() < best[0]): best = (m.start(), name)
    return best[1] if best else None

def attempt():
    tmp = tempfile.mkdtemp(prefix='logindrv-')            # neutral cwd: a stray firmware file here must not matter
    sock = os.path.join(tmp, 'con.sock'); log = os.path.join(a.outdir, '%s.qemu.log' % a.name)
    cmd = qemu + ['-display', 'none', '-monitor', 'none', '-serial', 'unix:%s,server=on,wait=off' % sock,
                  '-d', 'guest_errors,unimp', '-D', log, '-trace', 'load_file']
    errf = os.path.join(a.outdir, '%s.qemu.stderr' % a.name)      # a file, not a pipe: nothing reads the pipe while the guest boots
    ef = open(errf, 'wb')
    p = subprocess.Popen(cmd, cwd=tmp, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=ef)
    c = None
    try:
        c = Console(sock); t0 = time.time()
        while not RE_OK.search(c.text()):
            if time.time() - t0 > a.t_ok: return 2, 'no ok prompt within %ds' % a.t_ok, c
            c.read(1.0)
        t_ok = time.time() - t0
        loaded = {}
        for l in open(log, errors='replace'):
            m = re.match(r'load_file name (\S+) location (\S+)', l)
            if m: loaded[os.path.basename(m.group(1))] = m.group(2)
        bad = {f: loaded[f] for f in FILES if f in loaded and os.path.dirname(loaded[f]) != os.path.abspath(a.fw)}
        missing = [f for f in FILES if f not in loaded]
        if bad or missing: return 1, 'firmware not from %s: %s missing: %s' % (a.fw, bad, missing), c
        since = len(c.buf); c.send(a.boot_cmd + '\n'); tb = time.time(); last = tb
        while True:
            if c.read(1.0): last = time.time()
            t = c.text(since); st = earliest(t)
            if st == 'LOGIN': return 0, 'login prompt %ds after `%s` (ok prompt after %ds)' % (time.time() - tb, a.boot_cmd, t_ok), c
            if st == 'PANIC':
                m = re.search(r'panic\[cpu[0-9]+\][^\n]*', t)
                return 1, 'panic: %s' % (m.group(0)[:120] if m else ''), c
            if st == 'OBP-L14': return 2, "OpenBoot loader flake (`Last Trap: Level 14`), %ds after `%s`" % (time.time() - tb, a.boot_cmd), c
            if st in ('OBP-TRAP', 'OBP-RED'): return 1, 'OpenBoot trap after `%s`: %s' % (a.boot_cmd, [l for l in t.split('\n') if 'Trap' in l or 'Red State' in l][:1]), c
            if re.search(r'\nok $', t): return 1, 'the OpenBoot prompt came back: `%s` did not boot (no disk or no kernel?)' % a.boot_cmd, c
            if time.time() - last > a.t_stall: return 1, 'nothing on the console for %ds' % a.t_stall, c
            if time.time() - tb > a.t_login: return 1, 'no login prompt within %ds' % a.t_login, c
            if p.poll() is not None: return 2, 'QEMU exited (rc %s): %s' % (p.returncode, open(errf, 'rb').read()[-2000:].decode('latin1')), c
    except (EOFError, RuntimeError) as e:
        return 2, 'QEMU/console: %s; stderr: %s' % (e, (open(errf, 'rb').read()[-2000:] if p.poll() is not None else b'').decode('latin1')), c
    finally:
        ef.close()
        p.terminate()
        try: p.wait(10)
        except Exception: p.kill()

rc = 2
for n in range(1, a.attempts + 1):
    rc, msg, c = attempt()
    if c: open(os.path.join(a.outdir, '%s.console' % a.name), 'w').write(c.text())
    if rc == 0:
        print('ok  %-8s %s%s' % (a.name, msg, '' if n == 1 else '   WARNING: passed on attempt %d of %d' % (n, a.attempts)))
        sys.exit(0)
    print('%s %-8s attempt %d/%d: %s' % ('FAIL' if rc == 1 else 'try ', a.name, n, a.attempts, msg), file=sys.stderr)
    if rc == 1: break
    if c: print('    last console lines:\n' + '\n'.join('      ' + l for l in c.text().split('\n')[-6:]), file=sys.stderr)
sys.exit(rc)
