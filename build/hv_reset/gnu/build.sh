#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Build the OpenSPARC T2 q.bin/reset.bin with a stock GNU cross toolchain --
# no Sun Studio, no Sun as, no stabs, no SunPro make. Sun's aschk, which checks the assembler
# sources against offsets.chk, is built from source here (see "aschk" below).
#
# Notes on the layout:
#   - T2 is this repo's vendored src/hypervisor; ABI is abi/ next to this script (SPARC V9
#     ABI constants -- see abi/README).
#   - No T1 source is used. The assemble loop takes T2's own
#     greatlakes/common/src/end.s, confirmed byte-identical to T1's.
#   - PLATFORM/VARIANT default to ontario/legion, the validated target.
#   - QEMU_EXTRA_OPTIONS (build/hv_reset/options.mk) arrives via HV_EXTRA_OPTS
#     to hv-opts.sh. Same override hook, no separate mechanism.
#   - offsets.h is generated here if missing (build-offsets.sh), rather than
#     being a precondition the caller must satisfy.
#   - reset.bin is built here too, as its own step, with the GNU fixups reset.s
#     needs: -traditional-cpp and the .register wrapper.
#
# Usage: build.sh <workdir>
set -e

W=$1

[ -n "$W" ] || { echo "usage: build.sh <workdir>" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)

# The version string version.s bakes into q.bin, in Sun's own format:
# Makefile.family:56 has `QVERSION = Hypervisor $(RELEASE_VERSION) $(DATE)
# $(TIME)` with RELEASE_VERSION 0.1 -- Sun's number, not our release. This
# used to be a hardcoded "hv", which left GNU-built binaries with no way to
# tell when they were made. The date is build/stamp.sh's, the same one
# openboot.bin carries (SOURCE_DATE_EPOCH, else a clean commit's date, UTC),
# so two builds of one commit give the same q.bin.
eval "$("$REPO/build/stamp.sh" "$REPO")"
QVERSION=${QVERSION:-"Hypervisor 0.1 $STAMP_YMD $STAMP_HM"}
T2=$REPO/src/hypervisor/src
ABI=$HERE/abi
PLATFORM=${PLATFORM:-ontario}
VARIANT=${VARIANT:-legion}

mkdir -p "$W"
cd "$W"

if [ ! -f offsets.h ] || [ ! -f offsets.chk ]; then
    echo "=== offsets.h or offsets.chk missing, generating ==="
    sh "$HERE/build-offsets.sh" "$PWD"
fi

# ----------------------------------------------------------------- aschk ---
# Sun's Makefile.platform has `q: chkasm`: aschk reads every .s of the hypervisor and checks each
# load and store that names an offsets.h constant against offsets.chk (the size and the type of the
# field), and the build stops on a mismatch. It is a plain C program that runs no SPARC code, so it
# runs here too, built from Sun's source in a copy of support/aschk with two small fixes
# (patches/hv/gnu/aschk-host-build.patch). It reads the sources as they are in src/, not the
# srcfix/ versions: the same files, and the same offsets.chk, as on the sun path.
# The -include flags give the headers that Solaris brought in by itself. CC is the host compiler and
# its -std, as for build/mdtools/gnu/build.sh (make passes "$(HOST_GCC) $(HOST_CSTD)"): basics.h
# defines `false` and `true` as enumerators, which C23, the default of gcc 15 and later, makes
# keywords, so those need HOST_CSTD=-std=gnu17 (./configure sets it).
WD=$PWD
rm -rf aschk; mkdir aschk
cp "$T2"/support/aschk/*.c "$T2"/support/aschk/*.h "$T2"/support/aschk/*.l aschk/
patch -s -p1 -d aschk -i "$REPO/patches/hv/gnu/aschk-host-build.patch" </dev/null \
    || { echo "aschk-host-build.patch failed to apply" >&2; exit 1; }
${CC:-gcc} -O1 -w -include stdint.h -include stdlib.h -include string.h -include stdio.h \
    -Werror=implicit-function-declaration -Werror=implicit-int \
    -o aschk/aschk aschk/aschk_main.c aschk/ashash.c aschk/aslex.c > aschk/build.log 2>&1 \
    || { echo "ASCHK BUILD FAIL" >&2; cat aschk/build.log >&2; exit 1; }
( cd "$T2" && "$WD/aschk/aschk" -u -s -n "$WD/offsets.chk" \
      greatlakes/$PLATFORM/src/*.s greatlakes/common/src/*.s greatlakes/$PLATFORM/dumbreset/*.s common/src/*.s ) \
    > aschk.log 2>&1 \
    || { echo "ASCHK FAIL: an access in the assembler sources does not match offsets.chk" >&2; cat aschk.log >&2; exit 1; }
echo "aschk: the assembler sources match offsets.chk"

# The -D set comes straight out of the Makefiles (hv-opts.sh); mining the
# shipped binary also works but only for variants Sun actually shipped, and
# ontario/legion is not one of them.
OPTS="-D__sparcv9 $("$HERE/hv-opts.sh" "$PLATFORM" "$VARIANT")"

INC="-I$PWD/override -I$T2/greatlakes/$PLATFORM/include -I$T2/greatlakes/common/include \
 -I$T2/common/include -I$T2/include -I$ABI -I."

# ---------------------------------------------------------------- fixups ---
# Post-cpp rewrites for constructs Sun's as accepts and GNU as does not -- dialect
# differences, not source bugs. Kept as a build-time transform (not a real
# edit to src/hypervisor) because the repo's footnote format for a real,
# committed source fix is still being decided.
cat > fixup.sed <<'EOF'
s/\bwr[ \t]\+\([^,;]*\),[ \t]*%\(asi\|fprs\|gsr\|softint\|y\|pcr\|pic\)\b/wr \1, %g0, %\2/g
s/\bmov[ \t]\+\([^,;]*\),[ \t]*%\(asi\|fprs\|gsr\|softint\|y\)\b/wr %g0, \1, %\2/g
s/\b\(ldx\|stx\|ldub\|stb\|lduw\|stw\|ldd\|std\|ldsw\|lduh\|sth\)\[/\1 [/g
s/\[\(%[a-z][a-z0-9]*\)[ \t]\+\(0x[0-9a-f]\+\)\]/[\1 + \2]/g
s/\(\bb[a-z]*\),p\b/\1,pt/g
# `set` of a negative constant. Sun as treats set as a 32-bit operation and
# zero-extends (set -1 -> 0x00000000ffffffff); GNU as sign-extends to 64 bits
# (-> mov -1 = 0xffffffffffffffff) and only warns. ldc.s compares an lduw'd
# value against CONS_BREAK (-1) / CONS_HUP (-2), which a sign-extended constant
# can never equal. Masking makes gas fold it to sethi+or, as Sun's does.
s/\bset[ \t]\+\(-[0-9][0-9]*\)[ \t]*,/set (\1)\&0xffffffff,/
s/\bset[ \t]\+(\(-[0-9][0-9]*\))[ \t]*,/set (\1)\&0xffffffff,/
EOF

# Pre-cpp source fixes (cannot be done after preprocessing). Each is guarded:
# the set of affected files differs per platform. These four were originally
# described as "three latent bugs in Sun's source, not dialect differences" --
# checked against the real ontario/legion build 2026-09-14, and that
# classification holds for none of them as stated:
#   - errors_traps.s (SAVE_GLOBALS) is dead code for ontario/legion: absent
#     from TRAP_SRCS/Q_SRCS/PLATFORMC_SRCS in Makefile.platform, never
#     compiled or linked by either toolchain. Inert here.
#   - main.s (PRINTX) uses $PLATFORM, ontario by default -- but the actual
#     PRINTX("\r\n") bug lives only in greatlakes/huron/src/main.s:1100.
#     ontario/src/main.s has no such call (srcfix/main.s diffs empty against
#     pristine). Inert for the only validated target; would start mattering
#     only if huron is ever built (not a goal).
#   - svcinternal.s (missing `+`) is real and active on ontario/legion, but
#     it is a dialect difference like the fixup.sed rules above, not a logic
#     bug: Sun's as accepts `[reg symbol]` as implicit addition the same way it
#     accepts `[reg 0x...]`, which the fixup.sed regex two lines up already
#     handles for hex literals -- this one just uses a named constant
#     instead, so that regex doesn't catch it. Sun's toolchain compiles the
#     file completely unmodified and boots correctly; only GNU as refuses
#     the syntax.
# hvcontrol.c below is the one case where "not a dialect difference" still
# holds: cpp token-paste behavior plus gcc's stricter static/non-static
# declaration-order check, not something Sun's more permissive chain rejects.
mkdir -p srcfix
fix() {   # fix <relative-source> <sed-script...>
    src="$1"; shift
    [ -f "$src" ] || return 0
    sed -E "$@" "$src" > "srcfix/$(basename "$src")"
}
# SAVE_GLOBALS() takes no parameters (error_asm.h) but is called with one.
# Dead code for ontario/legion (see block comment above) -- inert here.
fix "$T2/greatlakes/$PLATFORM/src/errors_traps.s" \
    -e 's/SAVE_GLOBALS\([ \t]*%[a-z0-9]+[ \t]*\)/SAVE_GLOBALS()/g'
# PRINTX prints a hex value from a register; handed a string where PRINT was
# meant. Only true of huron/src/main.s, not ontario's -- inert here, kept for
# when/if huron is built (see block comment above).
fix "$T2/greatlakes/$PLATFORM/src/main.s" \
    -e 's/PRINTX\("\\r\\n"\)/PRINT("\\r\\n")/'
# `##` between a stringized token and a string literal (invalid ISO C
# token-paste -- adjacent string literals already concatenate without an
# operator; Sun's cpp tolerated the `##` anyway, GNU cpp does not); static
# after a non-static forward declaration (op_get_res_stat, prototyped
# non-static at line 88) two lines later. Both are genuine bugs in Sun's
# source, not dialect. Decided 2026-09-14: stays a build-time transform here,
# same as the dialect fixes above -- both toolchains already build and boot
# correctly as is, and a real source-level fix would need the
# still-undecided src/hypervisor marker format for no functional gain. Revisit only if that format gets decided
# for some other reason.
fix "$T2/common/src/hvcontrol.c" \
    -e 's/#_s##" : "##_n/#_s " : " _n/' \
    -e '757s/^static hvctl_status_t$/hvctl_status_t/'
# TTRACE_RELOC_ADDR does `setx .+8, ...` followed by `rd %pc`, meaning "the
# address of the rd". Sun as evaluates `.` at the last instruction of the
# expansion; GNU as at its first, and expands setx-with-a-symbol to six
# instructions, so the label lands 16 bytes early and every relocated %htba is
# off by 0x10. Harmless under QEMU (%htba is stored unmasked, so the wrong
# value is at least consistent), wrong on silicon. Six instructions = +24.
fix "$T2/common/src/hcall_core.s" -e 's/setx[[:space:]]+\.\+8,/setx .+24,/'
# A missing `+` inside [ ] two lines after the correct form. Dialect, not a
# bug -- see block comment above.
if [ -f "$T2/greatlakes/common/src/svcinternal.s" ]; then
    sed 's/\[r_svc SVC_CTRL_STATE\]/[r_svc + SVC_CTRL_STATE]/' \
        "$T2/greatlakes/common/src/svcinternal.s" > srcfix/svcinternal.s
fi

# PCIe device registers: assign the range in ra2pa_segment[] (which upstream
# only does under CONFIG_PCIE, unbuildable here) and let the real-mode TLB miss
# path accept an IO segment. Without both, Solaris takes a data access
# exception on its first device register write. Full reasoning, and why only
# one of the two range tests is widened, in the patch's own header.
#
# Applied to a staging tree rather than through fix() above: it is a 38-line
# insertion plus a one-line edit across two files, which is a patch, not a sed
# expression. src/hypervisor itself stays untouched, same as every fixup here.
mkdir -p hvfix/common/src hvfix/common/include
cp "$T2/common/src/res_guest.c"    hvfix/common/src/
cp "$T2/common/include/segments.h" hvfix/common/include/
patch -s -p1 -d hvfix -i "$REPO/patches/hv/hv-pcie-ra-segments.patch" </dev/null \
    || { echo "hv-pcie-ra-segments.patch failed to apply" >&2; exit 1; }
cp hvfix/common/src/res_guest.c      srcfix/res_guest.c
mkdir -p override
cp hvfix/common/include/segments.h   override/segments.h   # -I$PWD/override is first in INC

# gcc synthesises memcpy for some struct assignments; Sun's cc did not, and the
# hv has none of its own.
cat > memcpy_shim.c <<'EOF'
typedef unsigned long size_t_;
void *memcpy(void *d, const void *s, size_t_ n);
void *memcpy(void *d, const void *s, size_t_ n)
{ unsigned char *dp = d; const unsigned char *sp = s;
  while (n--) *dp++ = *sp++; return d; }
EOF

# ------------------------------------------------------------- assemble ---
for f in "$T2"/common/src/*.s "$T2"/greatlakes/common/src/*.s \
         "$T2/greatlakes/$PLATFORM/src"/*.s; do
    b=$(basename "$f")
    if [ -f "srcfix/$b" ]; then cp "srcfix/$b" .; else cp "$f" .; fi
    { printf '#include <sys/stack.h>\n'
      for r in g2 g3 g6 g7; do printf '\t.register\t%%%s, #scratch\n' "$r"; done
      printf '#include "%s"\n' "$b"; } > wrap.s
    # the preprocessor first, on its own: in a pipe its failure (a missing include, a bad macro) would not be seen
    sparc64-linux-gnu-gcc -E -traditional-cpp -x assembler-with-cpp -D_ASM \
        $OPTS $INC -DVERSION="\"$QVERSION\"" -DINFO="\"greatlakes:$PLATFORM:$VARIANT\"" \
        wrap.s > "${b%.s}.i" 2>"${b%.s}.cpp.err" || cpp_rc=$?
    # -traditional-cpp rejects three macro definitions in vpci_errs.h and exits non-zero, but writes the whole output; the build has
    # always gone on from there. Any other error is a failure, and so is a failure without any error line.
    if [ "${cpp_rc:-0}" != 0 ]; then
        other=$(grep -i 'error' "${b%.s}.cpp.err" | grep -v 'vpci_errs\.h:[0-9]*: error: syntax error in macro parameter list' || true)
        if [ -n "$other" ] || ! grep -qi 'error' "${b%.s}.cpp.err"; then
            echo "CPP FAIL $b (exit $cpp_rc)" >&2; cat "${b%.s}.cpp.err" >&2; exit 1
        fi
    fi
    cpp_rc=
    python3 "$HERE/pushlocals.py" < "${b%.s}.i" > "${b%.s}.pl.s" \
        || { echo "PUSHLOCALS FAIL $b" >&2; exit 1; }
    sed -f fixup.sed "${b%.s}.pl.s" > "${b%.s}.pp.s"
    sparc64-linux-gnu-as -Av9d -o "${b%.s}.o" "${b%.s}.pp.s" 2>"${b%.s}.err" \
        || { echo "ASM FAIL $b" >&2; cat "${b%.s}.err" >&2; exit 1; }
done

# --------------------------------------------------------------- compile ---
for f in "$T2"/common/src/*.c "$T2/greatlakes/$PLATFORM/src"/*.c \
         "$T2"/greatlakes/common/src/*.c memcpy_shim.c; do
    b=$(basename "$f"); s=$f
    [ -f "srcfix/$b" ] && s=srcfix/$b
    sparc64-linux-gnu-gcc -c -m64 $GNU_CSTD -mcpu=v9 -fPIC -O2 -fno-builtin -ffreestanding \
        -fno-tree-loop-distribute-patterns -fmacro-prefix-map="$T2=src/hypervisor/src" $OPTS $INC -o "${b%.c}.o" "$s" 2>"${b%.c}.err" \
        || { echo "C FAIL $b" >&2; cat "${b%.c}.err" >&2; exit 1; }
done

# ------------------------------------------------------------------ link ---
# Order matters: linking alphabetically puts callers out of WDISP16 reach of
# hvabort.  Sun's OBJS order keeps them close, so reproduce it.
python3 - > objorder.txt <<PY
import re, pathlib
mk = pathlib.Path("$T2/greatlakes/$PLATFORM/Makefile.platform").read_text()
def lst(v):
    m = re.search(rf"^{v}\s*=\s*((?:[^\n\\\\]*\\\\\n)*[^\n]*)", mk, re.M)
    return re.findall(r"[\w.]+\.[sc]", m.group(1)) if m else []
order = (["begin.s"] + lst("TRAP_SRCS") + lst("Q_SRCS") + lst("QC_SRCS")
         + lst("PLATFORMC_SRCS") + ["svc_init.c", "version.s", "end.s"])
seen = set()
for f in order:
    o = f.rsplit(".", 1)[0] + ".o"
    if o not in seen:
        seen.add(o); print(o)
PY

cat > q.ld <<'EOF'
/* GNU equivalent of greatlakes/common/src/mapfile.q.  The `|` entries there
   enforce section order so the build can size the GOT via _start_data. */
ENTRY(start_master)
SECTIONS {
  . = 0xfff0000000;
  .text : { *(.text) *(.rodata) *(.rodata.*) }
  _etext = .;
  /* .got must be immediately followed by .data, and _start_data -- which
     begin.s defines as the first thing in .data -- marks the end of the GOT.
     main.s walks _GLOBAL_OFFSET_TABLE_ .. _start_data relocating every entry
     when the hv copies itself to RAM.  Do NOT define _start_data here: a
     linker-script assignment overrides the object's symbol, the loop bounds
     collapse, no GOT entry is relocated, and every pointer loaded through the
     GOT silently keeps its link-time address. */
  /* .data.rel* must be collected here too.  gcc -fPIC puts tables holding
     relocatable pointers -- inittable in mdsup.c, for one -- into
     .data.rel.local, which Sun's mapfile never had to mention.  Leave it out
     and ld makes it an orphan section placed outside this segment: the hv then
     computes the right address for the table and finds zeros in it, and the
     only symptom is "Missing root node in HVMD" from a perfectly good MD. */
  .data : { *(.got) *(.data) *(.data.rel*) *(.data1) *(.sdata) }
  _edata = .;
  .bss  : { *(.bss) *(COMMON) }
  _end = .;
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame) }
}
EOF

OBJS=$(while read o; do [ -f "$o" ] && printf '%s ' "$o"; done < objorder.txt)
# --no-warn-execstack: a ROM image has no userland stack for a .note.GNU-stack
# to describe; the warning (binutils >= 2.39) is about end.o lacking one.
# Affects nothing objcopy -O binary emits.
sparc64-linux-gnu-ld -o q.elf -T q.ld -z defs --no-warn-execstack $OBJS memcpy_shim.o
sparc64-linux-gnu-objcopy -O binary q.elf q.bin
sparc64-linux-gnu-size q.elf

# ---------------------------------------------------------- reset.bin ---
# reset.s has always needed its own GNU-toolchain fixups (-traditional-cpp,
# the .register wrapper). Kept as its own step
# rather than folded into the assemble loop above: reset.s is not part of
# Q_SRCS, has no offsets.h dependency, and gets linked separately with its
# own script (reset.ld), matching how Sun's own Makefile treats it too.
cat > reset-wrap.s <<'EOF'
	.register	%g2, #scratch
	.register	%g3, #scratch
	.register	%g6, #scratch
	.register	%g7, #scratch
#include "reset-src.s"
EOF
cp "$T2/greatlakes/$PLATFORM/dumbreset/reset.s" reset-src.s

cat > reset.ld <<'EOF'
ENTRY(start_reset)
SECTIONS {
  . = 0xfff0000000;
  .text : { *(.text) *(.rodata) *(.data) *(.data1) *(.bss) }
  /DISCARD/ : { *(.comment) *(.note*) }
}
EOF

# reset.s aligns its trap table to 0x8000, and GNU as then rounds the section up
# to that alignment: reset.bin would be 32 KB, 768 bytes of code and nops after
# them. Sun's as ends the section at the code (768 bytes). --no-pad-sections
# does the same here; a binutils without the option gets the 32 KB file, with
# the same code.
PADFLAG=
echo | sparc64-linux-gnu-as -Av9d --no-pad-sections -o nopad-probe.o - 2>/dev/null \
    && PADFLAG=,--no-pad-sections
rm -f nopad-probe.o
sparc64-linux-gnu-gcc -c -x assembler-with-cpp -traditional-cpp -D_ASM \
    -Wa,-Av9d$PADFLAG $OPTS $INC -I. -o reset.o reset-wrap.s
sparc64-linux-gnu-ld -o reset.elf -T reset.ld --no-warn-execstack reset.o
sparc64-linux-gnu-objcopy -O binary reset.elf reset.bin

echo
echo "=== done ==="
ls -l q.bin reset.bin
