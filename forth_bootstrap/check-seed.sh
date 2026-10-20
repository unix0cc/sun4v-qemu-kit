#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# check-seed.sh -- derive step 1 of the OBP bootstrap from source and compare it with the files Sun shipped.
#
# Sun's metacompiler (fm/meta + fm/kernel/sparc/loadkern.fth, XREF on) is run by cforth built for sparc32 under
# qemu-user, on the unmodified src/obp/obp, and must write kernel-xref.dic and the two nheads listings that are
# byte-identical to the files Sun shipped in src/obp/obp/fm/kernel/sparc. No dictionary binary of Sun's or FirmWorks' is read: cforth's root is C
# (its `meta` + interp.fth). About a second once cforth is built.
#
#   Env: FB_WORK, FB_BP (default <repo>/src/obp/obp; read only).  Output: $FB_WORK/seed-cf/.
#   Exit 0 identical, 1 different, 77 skip.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/fbwork.sh"
BP=${FB_BP:-$(cd "$HERE/.." && pwd)/src/obp/obp}
SHIPPED=$BP/fm/kernel/sparc
CF=$("$HERE/build.sh") || exit $?
OUT=$W/seed-cf; R=$W/step1; rm -rf "$OUT" "$R"; mkdir -p "$OUT" "$R"; cd "$R" || exit 1
export BP
echo '" kernel-xref.dic" " dic-file-name" sym-set' > sym.fth
printf 'metaoff\n.( @@NHEADS) cr nheads\n.( @@NHEADLESS) cr nheadless\n.( @@END) cr\nbye\n' > post.fth
timeout 600 "$CF/forth" "$CF/app.dic" "$HERE/host/shim.fth" "$HERE/host/hooks.fth" "$HERE/host/xrefhooks.fth" \
    sym.fth "$HERE/host/pre.fth" "$BP/fm/meta/conft32.fth" "$BP/fm/kernel/sparc/loadkern.fth" post.fth \
    </dev/null > step1.log 2>&1
python3 - <<'PY' || { echo "FAIL: no listings in $R/step1.log" >&2; exit 1; }
t=open('step1.log',errors='replace').read()
a=t.index('@@NHEADS\n')+9; b=t.index('@@NHEADLESS\n'); c=t.index('@@END')
open('nh.txt','w').write(t[a:b]); open('nl.txt','w').write(t[b+12:c])
PY
[ -s kernel-xref.dic ] || { echo "FAIL: cforth wrote no kernel-xref.dic, see $R/step1.log" >&2; exit 1; }
cp kernel-xref.dic "$OUT/"
# The listings Sun shipped begin with a 41-line copyright banner; the run's output does not: take the banner of
# Sun's own copy in src/obp (the same file, read only), so that the output is the shipped file as it stands.
for f in kernel-xref.fth kernel-xref.headless.fth; do head -41 "$BP/fm/kernel/sparc/$f" > "$OUT/$f"; done
LC_ALL=C sort -k2 < nh.txt >> "$OUT/kernel-xref.fth"
LC_ALL=C sort -k2 < nl.txt >> "$OUT/kernel-xref.headless.fth"
rc=0
for f in kernel-xref.dic kernel-xref.fth kernel-xref.headless.fth; do
    if cmp -s "$OUT/$f" "$SHIPPED/$f"; then echo "  identical  $f"; else echo "  DIFFERENT  $f" >&2; rc=1; fi
done
if [ $rc = 0 ]; then echo "check-seed: cforth/sparc32 derives Sun's kernel-xref files from source, byte for byte (sha256 $(sha256sum < "$OUT/kernel-xref.dic" | cut -c1-16)...)"
else echo "check-seed: FAILED, see $R/step1.log" >&2; fi
exit $rc
