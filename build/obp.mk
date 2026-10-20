# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# openboot.bin -- OBP (Open Boot PROM) for sun4v/niagara.
#
#   make obp
#
# Two build paths, picked by TOOLCHAIN like every other component:
#
#   sun  Sun's own makefiles under /usr/ccs/bin/make with Sun Studio, on
#        Solaris/SPARC. obp-build below. The reference every GNU-path claim is
#        measured against.
#   gnu  build/obp/gnu/: the same Sun sources, GNU make, sparc64-linux-gnu
#        cross tools, and the Forth engine plus the OBMD-writing host tools
#        cross-built for sparc64 and run under a qemu-sparc64 linux-user
#        emulator. The dictionary images it needs are native SPARC code with
#        no source, which is why the engine must execute SPARC -- the
#        emulator is what lifts the old "Solaris only" restriction. Output
#        verified byte-identical to the sun path for every artefact but the
#        two that embed engine-binary addresses; see tests/full/obp/TESTS.
#
# There is no prebuilt fallback any more. A host that lacks the gnu tools
# fails loudly in check-obp-toolchain-gnu rather than copying a stale image
# (sparc-blob/ was retired 2026-09-22 for exactly that reason).
#
# Part of `all`: it needs every ROM in FIRMWARE, and both paths build on
# their own host, so obp sits there like the rest.
#
# OBP_PLATFORM/OBP_TARGET come from config.mk, coupled to TARGET:
# niagara/t1_fpga for legion, niagara1-hw/release for pci. The two must match,
# since only niagara1-hw/release carries sun4v-vpci and only niagara/t1_fpga
# carries SUNW,legion-disk.
#
# Note niagara/t1_fpga and niagara/release produce the SAME image.
# arch/common.mk defaults DROPIN_SRC to ${PLATFORM}/release/dropins.src and no
# Makefile sets DROPINSRC, so t1_fpga/dropins.src -- the only file that
# distinguishes them -- is never read. Sun's own shipped t1_fpga/openboot.bin
# has no t1-fpga-snet either. Do not "fix" this without a reason.

OBP_SRC  := src/obp
# Sun's makefiles build in place. Copy the tree out first: an in-tree build
# would leave ~50 products in src/obp.
#
# The leaf name used to reach the boot banner: release.mk's SUBREL sets
# $Wspace to `basename $ROOT`, five levels up from $(OBP_BLD), i.e. exactly
# $(OBP_WORK). SUB-RELEASE is now overridden (obp-build below), so it no
# longer does; the name is kept so the tree still says what it is.
OBP_WORK := $(WORKDIR)/sun4v-qemu-kit
OBP_BLD  := $(OBP_WORK)/obp/arch/sun4v/$(OBP_PLATFORM)/$(OBP_TARGET)

# --- gnu path ---------------------------------------------------------------
# build/obp/gnu/build-obp.sh is the driver; it builds the engine and host
# tools and then openboot.bin: the image goes to $(OUTDIR)/openboot.bin, the engine
# to $(WORKDIR)/obp-gnu/engine (cached across runs), the scratch tree to
# $(WORKDIR)/obp-gnu/<platform>-<target>.
# It walks the dropin chain itself (verify-dropin-chain.sh) before the image
# is final.
OBP_GNU_DIR := build/obp/gnu

.PHONY: obp obp-clean obp-build obp-gnu obp-verify obp-test obp-test-external \
        check-obp-toolchain check-obp-toolchain-gnu

ifeq ($(TOOLCHAIN),sun)
obp: obp-build
else
obp: obp-gnu
endif

# The compilers ./configure chose reach build-obp.sh and the makes it starts through the environment.
export HOST_GCC GNU_CSTD

# MAKEFLAGS= : the makes build-obp.sh starts must not read this make's -jN: it passes no jobserver to them (the recipe has no +), and
# they would print "jobserver unavailable: using -j1". The OBP chain is sequential by nature, so -jN is accepted and has no effect.
obp-gnu: check-obp-toolchain-gnu
	@[ -d $(OBP_SRC) ] || { echo "$(OBP_SRC) missing" >&2; exit 2; }
	MAKEFLAGS= QEMU_SPARC64="$(QEMU_SPARC64)" QEMU_SPARC32="$(QEMU_SPARC32)" \
	OUTDIR="$(OUTDIR)" WORKDIR="$(WORKDIR)" OBP_GNU_REPO="$(CURDIR)" \
	    $(OBP_GNU_DIR)/build-obp.sh $(OBP_PLATFORM)/$(OBP_TARGET)

# The equivalence gate (tests/full/obp/TESTS, tests/full/obp/run), Linux only and
# self-contained: the kernels and host dictionaries bootstrapped in a pci
# build must reconcile with the ones Sun shipped in src/obp; a second
# bootstrap generation from our own root must reproduce it; pristine builds
# of niagara2/release and niagara/t1_fpga must reproduce every dropin record
# of the openboot.bin Sun itself built for them (hashes in
# tests/full/obp/expected/sun-records.sha256, taken from the OpenSPARC tarball);
# a pristine-vs-patched pci build must differ only where this project's own
# patches say it should; the pci build's dictionary word list must match
# expected/dict-dump.sha256. No tarball, no Solaris host. `obp-verify` is
# kept as the long-standing name for this target; `obp-test` is the same
# thing. Independent of TARGET. ~1.5 min.
obp-verify: obp-test
obp-test: check-obp-toolchain-gnu
ifeq ($(TOOLCHAIN),sun)
	@echo "obp-test checks the gnu path; nothing to do on the sun path itself" >&2; exit 2
else
	@type python3 >/dev/null 2>&1 || { echo "obp-test needs python3" >&2; exit 2; }
	@rm -rf '$(WORKDIR)/obp-test'
	QEMU_SPARC64="$(QEMU_SPARC64)" QEMU_SPARC32="$(QEMU_SPARC32)" \
	OUTDIR="$(WORKDIR)/obp-test" \
	    tests/lib/gate.sh obp tests/full/obp/run
endif

# The external half: needs OpenSPARCT2_Arch.1.2.tar.bz2 (OPENSPARC_T2=<path>,
# or pass it as the first argument via TARBALL=). Confirms src/obp and
# src/hypervisor really are what Sun shipped (not just internally
# self-consistent, which src-intact -- part of obp-test above -- already
# checks), and is how tests/full/obp/expected/*.sha256 get regenerated and
# reviewed after a src/obp change. Not run by obp-test; run by hand, rarely.
obp-test-external: check-obp-toolchain-gnu
ifeq ($(TOOLCHAIN),sun)
	@echo "obp-test-external checks the gnu path; nothing to do on the sun path itself" >&2; exit 2
else
	@[ -n "$(TARBALL)$(OPENSPARC_T2)" ] || \
	    { echo "obp-test-external needs TARBALL=<OpenSPARCT2_Arch.1.2.tar.bz2> or OPENSPARC_T2=" >&2; exit 2; }
	tests/full/obp/external/src-pristine.sh $(TARBALL)
endif

# Everything the gnu path executes, by name, so a fresh host learns the whole
# list at once instead of one missing tool per attempt. QEMU_SPARC64/32 may be
# a bare name (PATH lookup) or a path; `type` handles both. The -m32 check
# asks the cross gcc where its 32-bit libc.a is: without the multilib it
# answers with the bare name.
check-obp-toolchain-gnu:
	@missing=; \
	for t in sparc64-linux-gnu-gcc sparc64-linux-gnu-ld sparc64-linux-gnu-size \
	         sparc64-linux-gnu-objcopy $(HOST_GCC) ar $(PATCH) awk cmp od sha256sum \
	         "$(QEMU_SPARC64)" "$(QEMU_SPARC32)"; do \
	    type "$$t" >/dev/null 2>&1 || missing="$$missing $$t"; \
	done; \
	[ -f "`sparc64-linux-gnu-gcc -m32 -print-file-name=libc.a 2>/dev/null`" ] || \
	    missing="$$missing sparc64-linux-gnu-gcc(-m32)"; \
	[ -z "$$missing" ] || { \
	    echo "openboot.bin (gnu path) needs tools this host lacks:$$missing" >&2; \
	    echo "  cross: apt install gcc-sparc64-linux-gnu binutils-sparc64-linux-gnu gcc-13-multilib-sparc64-linux-gnu" >&2; \
	    echo "  emulator: apt install qemu-user-static, or set QEMU_SPARC64=/QEMU_SPARC32=<path> -- see REQUIREMENTS.LINUX" >&2; \
	    exit 2; }

# --- sun path ---------------------------------------------------------------
# OBP_FIRMWAREREL overrides obp-release on both paths (default: build/stamp.sh's
# STAMP_OBP_RELEASE, 4.x.build_122+qemu[-<release>]); see obp-gnu.mk for the
# constraints on it. OBP_SUN_STAMP is expanded in a shell that has sourced
# $(OBP_WORK)/.stamp; \# because a bare # would start a make comment.
OBP_FIRMWAREREL ?=
OBP_SUN_STAMP = "SUB-RELEASE=[ sun4v-qemu-kit $$STAMP_MDY_HM git $$STAMP_REV \#0]" \
                "FIRMWAREREL=echo $$STAMP_OBP_RELEASE" \
                "DATEFMT='+$$STAMP_TD'"

# A cc that turns copy and clear loops into _memcpy/_memset calls (config.mk, SUN_CC_NOBUILTIN)
# leaves decomp.o -- target code, linked into the PROM image without a libc -- with an
# undefined _memset. Given as CC= to every Sun make below; the wrapper puts -xbuiltin=%none
# after the options, because decomp.c is compiled with -fast, which implies -xbuiltin=%all.
OBP_CC_ARG = $(if $(SUN_CC_NOBUILTIN),CC=$(SUN_CC_NOBUILTIN))
# decomp-size as a command-line override of arch/common.mk's DECOMPSIZE: see build/obp/decomp-size-sun.sh.
OBP_DSIZE_ARG = DECOMPSIZE=`sh $(CURDIR)/build/obp/decomp-size-sun.sh $(OBP_BLD)/decomp.o`

obp-build: check-obp-toolchain
	@[ -d $(OBP_SRC) ] || { echo "$(OBP_SRC) missing" >&2; exit 2; }
	rm -rf $(OBP_WORK)
	@mkdir -p $(dir $(OBP_WORK))
	cp -Rp $(OBP_SRC) $(OBP_WORK)
	@#
	@# Bind the Ophir FCode to QEMU's e1000 so `boot net` has a driver, and
	@# make the node's `reg` describe QEMU's BAR layout rather than the
	@# 82571's. Both halves are needed: with the binding alone, Solaris'
	@# e1000g fails to attach with "Mapping registers failed", because an
	@# 82540 is one of the MAC types whose regs_map REQUIRES an I/O BAR and
	@# the 82571's `reg` has no entry at 0x14. See the patch header.
	@#
	@# Re-enabled 2026-09-08. It was carried disabled from 2026-08-30 on a
	@# diagnosis that turned out to be wrong -- the 64-bit space code, which
	@# px translates on its own.
	$(PATCH) -s -p1 -d $(OBP_WORK) -i $(CURDIR)/patches/obp/forth/ophir-qemu-e1000.patch </dev/null
	@#
	@# Let the IDE driver detect a drive under QEMU, whose software reset
	@# finishes too fast for the BSY check to see. See the patch header.
	$(PATCH) -s -p1 -d $(OBP_WORK) -i $(CURDIR)/patches/obp/forth/ide-srst-no-bsy-check.patch </dev/null
	@#
	@# Guard md-iodevice-props.fth's find-child-device against a child with
	@# no "reg" -- Sun's code deref's a bad stack cell and hangs OBP before
	@# the banner. This is what lets its stand-init "pci-network" branch --
	@# the only code that stamps a per-NIC local-mac-address from the MD's
	@# mac-addresses -- run on QEMU's flat switchless sun4v-pcie-host, where
	@# a `pci-network` iodevice node resolves against the nexus' own child
	@# list rather than a T2000's deep PCIe-switch tree.
	$(PATCH) -s -p1 -d $(OBP_WORK) -i $(CURDIR)/patches/obp/forth/md-iodevice-reg-guard.patch </dev/null
	@#
	@# Skip the Ophir FCode's EEPROM-MAC sync (pkg.fth update-mac-address).
	@# Once find-my-mac-addr reads the MD's mac-addresses it bit-bangs the
	@# card EEPROM (eeprom-w@/eeprom-w!) to match; QEMU's 82540 EEPROM is
	@# synthesised from -device mac= and the bit-bang wait never completes,
	@# hanging OBP before its banner the moment a mac-addresses property is
	@# present.
	$(PATCH) -s -p1 -d $(OBP_WORK) -i $(CURDIR)/patches/obp/forth/ophir-skip-eeprom-mac-sync.patch </dev/null
	@#
	@# elf2bin drops the gap between reset.elf's .text and .data when the image starts at
	@# address 0; Developer Studio 12.6's decomp.o has one (8-aligned .data), so the
	@# decompressor looks for its magic bytes at the wrong place and the PROM is silent.
	@# See the patch header.
	$(PATCH) -s -p1 -d $(OBP_WORK) -i $(CURDIR)/patches/obp/sun/elf2bin-keep-section-gap.patch </dev/null
	@#
	@#
	@# The build stamp, from build/stamp.sh like the gnu path's: the same
	@# obp-release, sub-release and compile-signature, byte for byte, and
	@# the same date (SOURCE_DATE_EPOCH, else the clean commit's, UTC). It is
	@# handed to Sun's make as command-line macros, which override the
	@# makefile's own, so no Sun makefile is edited:
	@#   SUB-RELEASE  replaces release.mk's SUBREL, whose [$$Uid $$Wspace
	@#                $$Comment #$$Revlevel] carries logname and the build
	@#                directory's name -- neither belongs in a reproducible image;
	@#   FIRMWAREREL  `cat firmware.rel` becomes `echo <STAMP_OBP_RELEASE>`;
	@#   DATEFMT      the bootprom recipe runs `date $${DATEFMT}` for
	@#                compile-signature. A format with no % conversions is
	@#                printed as-is, so the macro carries the finished Forth
	@#                text. The leading + keeps date(1) in format mode -- on
	@#                Solaris, date with a bare mmddHHMM operand SETS the clock.
	@# Every Sun make below gets them: `make reset.bin` already builds
	@# bootprom.bin (reset.o <- stand.dic <- bootprom.bin), so version.fth is
	@# written there, not in the final `make openboot.bin`.
	sh $(CURDIR)/build/stamp.sh $(CURDIR) > $(OBP_WORK)/.stamp
	[ -z '$(OBP_FIRMWAREREL)' ] || echo "STAMP_OBP_RELEASE='$(OBP_FIRMWAREREL)'" >> $(OBP_WORK)/.stamp
	@cat $(OBP_WORK)/.stamp
	@# (1) arch/common.mk includes dropins.mk, which it also generates
	@#     (:399). Sun make treats a missing include as fatal and will not
	@#     remake it first, so the generating rule is unreachable. Seed one.
	: > $(OBP_BLD)/dropins.mk
	@#
	@# (2) DECOMPSIZE is ${DECOMPSIZ:sh} -- `size -f decomp.o` run when the
	@#     makefile is PARSED, not when the rule fires. On a clean tree
	@#     decomp.o does not exist, so it expands empty and reset.o compiles
	@#     with a malformed `d#  constant decomp-size`. Build decomp.o in
	@#     its own invocation so the next parse can measure it.
	. $(OBP_WORK)/.stamp && cd $(OBP_BLD) && SUN_STUDIO=$(SUN_STUDIO) SIM_ROOT=$(OBP_WORK) $(MAKE_SUN) decomp.o $(OBP_CC_ARG) $(OBP_SUN_STAMP)
	. $(OBP_WORK)/.stamp && cd $(OBP_BLD) && SUN_STUDIO=$(SUN_STUDIO) SIM_ROOT=$(OBP_WORK) $(MAKE_SUN) dropins.mk $(OBP_CC_ARG) $(OBP_SUN_STAMP)
	@#
	@# (3) reset.bin on its own, so it can be repaired before makeprom
	@#     consumes it -- see build/obp/pad-reset-bin.sh for what and why.
	. $(OBP_WORK)/.stamp && cd $(OBP_BLD) && SUN_STUDIO=$(SUN_STUDIO) SIM_ROOT=$(OBP_WORK) $(MAKE_SUN) reset.bin $(OBP_CC_ARG) $(OBP_DSIZE_ARG) $(OBP_SUN_STAMP)
	sh $(CURDIR)/build/obp/pad-reset-bin.sh $(OBP_BLD)/reset.bin
	. $(OBP_WORK)/.stamp && cd $(OBP_BLD) && SUN_STUDIO=$(SUN_STUDIO) SIM_ROOT=$(OBP_WORK) $(MAKE_SUN) openboot.bin $(OBP_CC_ARG) $(OBP_DSIZE_ARG) $(OBP_SUN_STAMP)
	@#
	@# (4) A broken dropin chain gives no diagnostic at all. The PROM dies
	@#     before printing one character. Never ship an image unwalked.
	sh $(CURDIR)/build/obp/verify-dropin-chain.sh $(OBP_BLD)/openboot.bin
	@mkdir -p $(OUTDIR)
	cp $(OBP_BLD)/openboot.bin $(OUTDIR)/
	@echo "openboot.bin -> $(OUTDIR)/openboot.bin"

check-obp-toolchain:
	@[ "`uname -s`" = SunOS ] || { \
	    echo "the sun path builds openboot.bin on Solaris/SPARC only; elsewhere use TOOLCHAIN=gnu -- see build/obp/README" >&2; exit 2; }
	@[ -x "$(SUN_STUDIO)/bin/cc" ] || { echo "no cc at $(SUN_STUDIO)/bin/cc -- set SUN_STUDIO=" >&2; exit 2; }
	@[ -x "$(MAKE_SUN)" ] || { echo "$(MAKE_SUN) not found -- need the SysV make, not gmake" >&2; exit 2; }

obp-clean:
	rm -rf $(OBP_WORK) $(WORKDIR)/obp-gnu $(WORKDIR)/obp-test $(OUTDIR)/openboot.bin
