#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# setx-rd-pc.sh -- wherever the hypervisor source relocates a label with `setx` and then reads `rd %pc`,
# the relocation points at that `rd %pc` itself.
#
# The pattern (util.h RELOC_OFFSET, hcall_core.s TTRACE_RELOC_ADDR):
#
#     setx   <label>, scr, reg      ! reg = link-time address of the label
#   <label>:
#     rd     %pc, scr                ! scr = run-time address of the same place
#     sub    reg, scr, reg           ! reg = link - run = the relocation delta
#
# TTRACE_RELOC_ADDR writes the label as `.+8`. Sun as evaluates `.` at the last instruction of the
# expansion, so the label lands on the rd. GNU as evaluates it at the first, and expands setx-with-a-symbol
# to six instructions, so the label landed 16 bytes early and every relocated %htba was off by 0x10 (fixed
# by `setx .+24` in build.sh's fix() for hcall_core.s). QEMU stores %htba unmasked, so the wrong value was
# self-consistent there and nothing visibly failed; on silicon it would not have been.
#
# Checks the object files, not the source: for every `rd %pc`, any HH22/LM22 relocation of a `.text+X`
# within the eight instructions before it and within 0x40 bytes of it must have X == the rd's address.
#
# Measured: on the tree before the fix it fails on the three TTRACE_RELOC_ADDR uses (each -16 bytes,
# reported twice, once per HH22 and LM22); after the fix 14 pairs are checked and none is off.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${OUTDIR:?set OUTDIR}"
"$HERE/../lib/build.sh"
type sparc64-linux-gnu-objdump >/dev/null 2>&1 || { echo "needs sparc64-linux-gnu-objdump" >&2; exit 2; }

python3 - "$OUTDIR" <<'PY'
import glob, re, subprocess, sys
bad = checked = 0
for o in sorted(glob.glob(sys.argv[1] + '/*.o')):
    # -m sparc:v9d: without it objdump does not decode %hver/%htba and friends
    out = subprocess.run(['sparc64-linux-gnu-objdump', '-dr', '-m', 'sparc:v9d', o],
                         capture_output=True, text=True).stdout
    ins = []                                  # [address, text, [(reloc type, symbol)]]
    for line in out.splitlines():
        m = re.match(r'^\s*([0-9a-f]+):\s+(?:[0-9a-f]{2} ){4}\s*(.*)$', line)
        if m:
            ins.append([int(m.group(1), 16), m.group(2), []]); continue
        m = re.match(r'^\s*[0-9a-f]+:\s+(R_SPARC_\w+)\s+(\S+)$', line)
        if m and ins:
            ins[-1][2].append((m.group(1), m.group(2)))
    for k, (addr, text, _) in enumerate(ins):
        if not re.match(r'rd\s+%pc,', text):
            continue
        for j in range(max(0, k - 8), k):
            for typ, sym in ins[j][2]:
                m = re.match(r'^\.text\+(0x[0-9a-f]+)$', sym)
                if typ in ('R_SPARC_HH22', 'R_SPARC_LM22') and m:
                    x = int(m.group(1), 16)
                    if abs(x - addr) <= 0x40:
                        checked += 1
                        if x != addr:
                            bad += 1
                            print('FAIL %s: setx targets .text+%#x but the rd %%pc is at %#x (%+d bytes)'
                                  % (o.rsplit('/', 1)[-1], x, addr, x - addr), file=sys.stderr)
if not checked:
    print('FAIL: no setx/rd %pc pair found at all -- the pattern changed or objdump stopped decoding', file=sys.stderr)
    sys.exit(1)
if bad:
    sys.exit(1)
print('ok: %d setx/rd %%pc relocation pairs checked, none off' % checked)
PY
