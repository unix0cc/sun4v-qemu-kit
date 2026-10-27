# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# hv_reset -- the hypervisor and its reset vector: q.bin and reset.bin.
#
#   make hv_reset                  # auto-detected toolchain
#   make hv_reset TOOLCHAIN=sun    # Sun Studio on Solaris, Sun's makefiles
#   make hv_reset TOOLCHAIN=gnu    # sparc64-linux-gnu cross tools, any host
#
# One component, two outputs. Sun builds them together: legion/Makefile
# declares `all :: reset.bin q.bin`. reset.s is the boot vector that sets up
# and enters the hypervisor, so they ship as a pair here too.
#
# Which options are set and why is in build/hv_reset/options.mk.
#
# Both paths apply patches/hv/hv-pcie-ra-segments.patch, never to
# src/hypervisor itself. Without it a guest cannot reach PCIe device registers
# at all. It changes hypervisor behaviour, not dialect, so wiring it into one
# toolchain only would leave the other silently broken.
#
# build/hv_reset/sun/ holds one file, nocap.mapfile; the rest of the sun path is
# "call Sun's build system", which fits in the recipe below. (A cc that writes no
# stabs also uses build/hv_reset/offsets-dwarf.sh, shared with the gnu path; see
# HV_STABS_PROBE and README.dwarf.) gnu/ is bigger
# because that path is a port: offsets.h without stabs, srcfix rewrites for
# constructs GNU as rejects, a memcpy shim. mdtools and obp are the same shape.

.PHONY: hv_reset hv_reset-clean hv-verify hv-test

# Both paths always ask the underlying build system. Incrementality is theirs.
FORCE:

ifeq ($(TOOLCHAIN),sun)

# ------------------------------------------------------------------ sun -----
# Sun's unmodified Makefile.master chain with Sun Studio cc. Three of its tool
# macros are overridden on the make command line, the way SysV make allows:
# AS= (system as instead of the one Sun shipped prebuilt, see AS_SUN in config.mk),
# LD= (system ld plus sun/nocap.mapfile), OBJCOPY= (system GNU objcopy).
# Options go through Sun's own EXTRA_OPTIONS= hook.
#
# PLATFORM/VARIANT/FAMILY/TOP need no setting here. They are hardcoded via
# relative TOP=../../.. chains inside the Makefiles. The one real external
# variable is SUN_STUDIO, because Makefile.master does COMPDIR = ${SUN_STUDIO}.
#
# Use /usr/ccs/bin/make, not gmake. These Makefiles use SysV/dmake syntax
# (`:sh=` macros, `.KEEP_STATE:`, target-specific macros) GNU make lacks.
#
# Makefile.platform invokes bare `size q`, and /usr/ccs/bin is not on a
# non-interactive shell's PATH. Without PATH set here a build over ssh fails at
# the last step with "size: not found". Do not rely on the login profile.
#
# Sun's makefiles build in place, so copy the tree out first. This repo keeps
# no intermediate state.
#
# `cp -Rp`, never `cp -a`: -a is a GNU extension and Solaris cp rejects it.
# Same trap as `sed -i` and `tar --strip-components`. Everything in the sun
# path runs under Solaris userland, so check a familiar flag before using it.
HV_WORK    := $(WORKDIR)/hv-build
LEGION_DIR := $(HV_WORK)/src/greatlakes/$(PLATFORM)/$(VARIANT)

# stabs and aschk are required, not optional. stabs generates offsets.h, and
# Makefile.platform's `q: chkasm $(OBJS)` puts chkasm (which runs aschk) on the
# path to q.bin. Both have sources here, so they are built and copied into
# hypervisor-tools/bin of the work copy, where Makefile.master expects them.
# Nothing prebuilt is used from that directory any more: the assembler,
# linker and objcopy all come from the system (AS_SUN, LD_SUN, OBJCOPY_SUN in
# config.mk). See build/hv_reset/README.options for why.
#
# Verified 2026-08-24 (stabs/aschk from source vs. Sun's prebuilt copies) and
# 2026-09-14 (system as + nocap.mapfile vs. Sun's prebuilt assembler): offsets.h and
# reset.bin byte-identical, q.bin differing only in the build timestamp and
# directory path it embeds. No difference in code or data.
SUP := $(HV_WORK)/src/support
NOCAP_MAPFILE := $(CURDIR)/build/hv_reset/sun/nocap.mapfile

# Oracle Developer Studio 12.6's cc writes no stabs (cc(1): "-xdebugformat=dwarf ... is
# the default. The option is obsolete"), which Sun's offsets.h/offsets.chk rules and
# `stabs` need. Probe the capability itself, not a version string: compile a struct
# with -xdebugformat=stabs and count the .stabs type lines (the .xstabs index lines
# are written by every cc and do not count). Sun Studio 11 and 12.x write them.
#
# When it has none, this differs, applied only then so that Sun Studio 11 builds exactly as
# before:
#   - patches/hv/hv-ds12-offsets-dwarf.patch swaps Sun's two offsets rules for calls to
#     build/hv_reset/offsets-dwarf.sh (reader: dwarf2genassym.pl; README.dwarf there),
#     which make offsets.h and offsets.chk from DWARF. Pre-making the files does not
#     work: with no .make.state Sun's make runs the stabs rule anyway.
# Separately (config.mk, SUN_CC_NOBUILTIN): a cc that turns copy and clear loops into
# calls to _memcpy/_memset, which the hypervisor, having no libc, cannot link, is given
# -xbuiltin=%none through build/cc-nobuiltin.sh. Developer Studio 12.6 is both.
HV_STABS_PROBE ?= $(shell d=$(WORKDIR)/stabsprobe; rm -rf $$d; mkdir -p $$d && \
    printf 'struct s { int a; };\nstruct s v;\n' > $$d/p.c && \
    ( cd $$d && $(SUN_STUDIO)/bin/cc -xdebugformat=stabs -g -S -o p.s p.c >/dev/null 2>&1; grep -c '\.stabs "' p.s 2>/dev/null ); \
    rm -rf $$d)
HV_DWARF = $(if $(filter-out 0,$(strip $(HV_STABS_PROBE))),,yes)
HV_DS_ARGS = $(if $(SUN_CC_NOBUILTIN),CC=$(SUN_CC_NOBUILTIN)) \
    $(if $(HV_DWARF),OFFSETS_GEN='sh $(CURDIR)/build/hv_reset/offsets-dwarf.sh -d $(SUN_STUDIO)/bin/dwarfdump -f dwarfdump')

.PHONY: check-sun-toolchain

hv_reset: check-sun-toolchain $(OUTDIR)/reset.bin $(OUTDIR)/q.bin

check-sun-toolchain:
	@[ -x "$(SUN_STUDIO)/bin/cc" ] || { echo "no cc at $(SUN_STUDIO)/bin/cc -- set SUN_STUDIO=" >&2; exit 2; }
	@[ -x "$(MAKE_SUN)" ] || { echo "$(MAKE_SUN) not found -- need the SysV make, not gmake" >&2; exit 2; }
	@# Solaris /usr/bin/patch cannot read a unified diff. It prompts for a
	@# filename instead, forever, on a build with no terminal. Insist on GNU
	@# patch up front rather than discovering this mid-build.
	@$(PATCH) --version >/dev/null 2>&1 || { \
	    echo "$(PATCH) is not GNU patch -- Solaris /usr/bin/patch cannot read unified diffs; set PATCH=/usr/bin/gpatch" >&2; exit 2; }
	@# Not `command -v`: on Solaris that is /usr/bin/command, a script that
	@# does not take -v, so the check fails on the host it is checking.
	@# Running flex is the better test anyway -- it proves the binary works,
	@# not just that a name resolves.
	@PATH=$(SUN_PATH); export PATH; $(FLEX) --version >/dev/null 2>&1 || { \
	    echo "$(FLEX) not runnable on $(SUN_PATH) -- set FLEX=/path/to/flex" >&2; exit 2; }
	@[ -x "$(OBJCOPY_SUN)" ] || { echo "no objcopy at $(OBJCOPY_SUN) -- SUNWbinutils not installed, set OBJCOPY_SUN=" >&2; exit 2; }
	@[ -x /usr/ccs/bin/mcs ] || { echo "no mcs at /usr/ccs/bin/mcs -- SUNWbtool not installed" >&2; exit 2; }
	@[ -x "$(LD_SUN)" ] || { echo "no ld at $(LD_SUN) -- set LD_SUN=" >&2; exit 2; }
	@# The hypervisor needs -xarch=v9d for the hyperprivileged registers. Only
	@# /usr/ccs/bin/as from SUNWsprot patch 118683-15 on accepts it; older ones
	@# (and Sun Studio 11's fbe) fail with "invalid register". Test on a real
	@# rdhpr rather than trusting a version string.
	@t=$(WORKDIR)/astest; rm -rf $$t; mkdir -p $$t; \
	    printf '\trdhpr\t%%hpstate, %%g1\n' > $$t/t.s; \
	    "$(AS_SUN)" -xarch=v9d -o $$t/t.o $$t/t.s >/dev/null 2>&1 || { \
	        echo "$(AS_SUN) does not accept -xarch=v9d / rdhpr -- need SUNWsprot patch 118683-15 (see REQUIREMENTS.SOLARIS), or set AS_SUN=" >&2; \
	        rm -rf $$t; exit 2; }; \
	    rm -rf $$t

# Both binaries come from one Sun `make all` (legion/Makefile's `all ::
# reset.bin q.bin`). Incrementality is Sun's .KEEP_STATE machinery. FORCE means
# "always ask Sun's make"; Sun's make decides what needs rebuilding.
$(OUTDIR)/reset.bin: FORCE
	rm -rf $(HV_WORK)
	@mkdir -p $(dir $(HV_WORK))
	cp -Rp src/hypervisor $(HV_WORK)
	$(PATCH) -s -p1 -d $(HV_WORK)/src -i $(CURDIR)/patches/hv/hv-pcie-ra-segments.patch </dev/null
	$(PATCH) -s -p1 -d $(HV_WORK)/src -i $(CURDIR)/patches/hv/hv-sun-strip-debug.patch </dev/null
	$(if $(HV_DWARF),@echo "this cc writes no stabs: offsets.h and offsets.chk from DWARF")
	$(if $(SUN_CC_NOBUILTIN),@echo "this cc turns loops into _memcpy/_memset calls: cc -xbuiltin=%none")
	$(if $(HV_DWARF),$(PATCH) -s -p1 -d $(HV_WORK)/src -i $(CURDIR)/patches/hv/hv-ds12-offsets-dwarf.patch </dev/null)
	cd $(SUP)/stabs && PATH=$(SUN_PATH) SUN_STUDIO=$(SUN_STUDIO) $(MAKE_SUN)
	cd $(SUP)/aschk && PATH=$(SUN_PATH) SUN_STUDIO=$(SUN_STUDIO) $(MAKE_SUN) LEX=$(FLEX)
	mkdir -p $(HV_WORK)/src/hypervisor-tools/bin
	cp $(SUP)/stabs/stabs $(SUP)/aschk/aschk $(HV_WORK)/src/hypervisor-tools/bin/
	@# DATE/TIME override Makefile.family's `date` :sh macros, which make up
	@# QVERSION ("Hypervisor 0.1 <DATE> <TIME>", the one date q.bin carries),
	@# with build/stamp.sh's -- the gnu path's, and openboot.bin's: the
	@# clean commit's date (or SOURCE_DATE_EPOCH), UTC. stamp.sh runs before
	@# PATH is narrowed, since it needs git. Not part of the stamp, and left
	@# alone: q.bin also carries the build directory, 16 times -- the
	@# DW_AT_comp_dir Sun cc writes for each hv C object even without -g,
	@# in .debug_* sections the link marks SHF_ALLOC, so objcopy -O binary
	@# keeps them. Two builds in the same OUTDIR give the same q.bin; in
	@# different ones they differ in those bytes only.
	eval "`sh $(CURDIR)/build/stamp.sh $(CURDIR)`" && \
	cd $(LEGION_DIR) && PATH=$(SUN_PATH) SUN_STUDIO=$(SUN_STUDIO) $(MAKE_SUN) all $(HV_DS_ARGS) \
	    EXTRA_OPTIONS="$(QEMU_EXTRA_OPTIONS)" \
	    AS=$(AS_SUN) LD="$(LD_SUN) -M $(NOCAP_MAPFILE)" OBJCOPY=$(OBJCOPY_SUN) \
	    DATE="$$STAMP_YMD" TIME="$$STAMP_HM"
	@mkdir -p $(OUTDIR)
	cp $(LEGION_DIR)/reset.bin $(LEGION_DIR)/q.bin $(OUTDIR)/

# One recipe makes both files. Listing both as targets of it would run it twice (a rule with several targets is one rule
# per target; grouped targets need GNU make 4.3, and Solaris 10's gmake is 3.82): every build was done twice and the second
# pass overwrote the first.
$(OUTDIR)/q.bin: $(OUTDIR)/reset.bin
	@:

hv_reset-clean:
	rm -rf $(HV_WORK)
	rm -f $(OUTDIR)/reset.bin $(OUTDIR)/q.bin

else

# ------------------------------------------------------------------ gnu -----
# Cross GNU toolchain (sparc64-linux-gnu-*). No Sun software at all.
#
# offsets.h is generated without Sun's stabs, by build-offsets.sh: gcc writes DWARF
# for a stub that refers to every type offsets.in names, and dwarf2genassym.pl reads
# the layout back with the semantics of `stabs -t genassym`. The result is
# byte-identical to a real Sun-toolchain offsets.h for this exact target,
# gnu/reference/offsets.ontario-legion.h (all 1161 names, none supplemented).
# The same values computed a second way (compiler-evaluated offsetof markers) are the
# offsets-cross-check test, tests/full/hv_reset.
export HV_EXTRA_OPTS := $(QEMU_EXTRA_OPTIONS)

HV_WORK := $(WORKDIR)/hv-build

hv_reset: $(OUTDIR)/reset.bin $(OUTDIR)/q.bin

$(OUTDIR)/reset.bin: FORCE
	@# Start from nothing, as the sun branch does: build.sh keeps an offsets.h it finds, and an .o left by an earlier run
	@# (other HV_OPTIONS, or one that failed to compile now) would be linked without a word.
	rm -rf $(HV_WORK)
	CC="$(HOST_GCC) $(HOST_CSTD)" PLATFORM="$(PLATFORM)" VARIANT="$(VARIANT)" sh build/hv_reset/gnu/build.sh $(HV_WORK)
	@mkdir -p $(OUTDIR)
	cp $(HV_WORK)/reset.bin $(HV_WORK)/q.bin $(OUTDIR)/

# Both files from one run of the recipe above, not two (see the sun branch).
$(OUTDIR)/q.bin: $(OUTDIR)/reset.bin
	@:

# Only what this component produces. Top-level `make clean` removes everything.
hv_reset-clean:
	rm -rf $(HV_WORK)
	rm -f $(OUTDIR)/reset.bin $(OUTDIR)/q.bin
endif

# The GNU path's gate: two checks that need no Sun build, no Solaris host and no QEMU (tests/full/hv_reset/README).
# They run the gnu build with the assembler's stderr visible and look at the objects, so they are about the
# port -- GNU as vs Sun as -- and say nothing about the sun path itself. ~10 s.
# `hv-verify` is the name that pairs with `obp-verify`; `hv-test` is the same thing.
hv-verify: hv-test
hv-test:
ifeq ($(TOOLCHAIN),sun)
	@echo "hv-test checks the gnu path; nothing to do on the sun path itself" >&2; exit 2
else
	@type python3 >/dev/null 2>&1 || { echo "hv-test needs python3" >&2; exit 2; }
	@rm -rf "$(WORKDIR)/hv-test"
	OUTDIR="$(WORKDIR)/hv-test" PLATFORM="$(PLATFORM)" VARIANT="$(VARIANT)" \
	CC="$(HOST_GCC) $(HOST_CSTD)" HV_EXTRA_OPTS="$(QEMU_EXTRA_OPTIONS)" \
	    tests/lib/gate.sh hv tests/full/hv_reset/run
endif
