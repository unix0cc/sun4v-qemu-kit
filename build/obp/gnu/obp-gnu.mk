# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# obp-gnu.mk -- builds openboot.bin on Linux/x86_64. Normally reached
# through `make obp` (build/obp.mk -> build-obp.sh), not run by hand.
# What it does differently from Sun's build, and why each difference is
# harmless, is inventoried in tests/full/obp/TESTS section 6.
#
# Status: verified end to end. Both machine configs build from clean through
# `make all` and boot Solaris 10 to console login (tests/full/obp/TESTS, the boots,
# T10); every product but the two saved Forth images is byte-identical to the
# Sun-toolchain reference, gated by `make obp-verify` (TESTS, section 3).
#
# Usage:
#   make -f build/obp/gnu/obp-gnu.mk OBP_PLATFORM=niagara      OBP_TARGET=t1_fpga
#   make -f build/obp/gnu/obp-gnu.mk OBP_PLATFORM=niagara1-hw  OBP_TARGET=release
#
# Requires (full list in REQUIREMENTS.LINUX):
#   sparc64-linux-gnu-{gcc,ld,size,objcopy} with the -m32 multilib, gcc,
#   patch, qemu-sparc64 and qemu-sparc32plus linux-user binaries
#   (QEMU_SPARC64/QEMU_SPARC32; Ubuntu's qemu-user-static has both).
#   The only shipped binary read is os/sun/sparc/forth.dic: every other
#   dictionary is bootstrapped from it (bootstrap-dics.sh).
#
# Principle: reuse Sun's own generated
# dropins.mk and every per-dropin depend.mk (plain target:deps, GNU-make
# compatible as-is) and the generic %.fc: pattern rule from arch/common.mk
# (copied verbatim in obp-gnu-inner.mk) -- only the tool-path variables
# change. The dropins-driven part of the build (dropins.mk plus every
# depend.mk it includes) is entirely bare, cwd-relative filenames --
# Sun's own build always `cd $(OBP_BLD) && gmake` first -- so that part
# runs as a sub-make invoked with -C $(OBP_BLD) against obp-gnu-inner.mk,
# rather than rewriting those paths to work from this file's own cwd.

SHELL := /bin/bash

# ---------------------------------------------------------------- config --

OBP_PLATFORM ?= niagara
OBP_TARGET   ?= t1_fpga

REPO       ?= $(abspath $(CURDIR)/../../..)
OBP_SRC    ?= $(REPO)/src/obp/obp
ENGINE_OUT ?= $(REPO)/build/obp/gnu/engine/out

QEMU_SPARC64      ?= $(error set QEMU_SPARC64 to a qemu-sparc64 linux-user binary)
QEMU_SPARC32      ?= $(error set QEMU_SPARC32 to a qemu-sparc32plus linux-user binary)
FORTH64_BIN       := $(ENGINE_OUT)/forth64
FORTH32_BIN       := $(ENGINE_OUT)/forth32
DIDEPEND_BIN      := $(ENGINE_OUT)/didepend
MAKEDI_SPARC_BIN  := $(ENGINE_OUT)/makedi-sparc
MAKEPROM_SPARC_BIN:= $(ENGINE_OUT)/makeprom-sparc

# The host dictionaries every Forth-run tool loads, bootstrapped into the
# build copy by bootstrap-dics.sh -- Sun's FORTHDIC and TOKENIZEDIC
# (forth.mk:73,78), on Sun's 32-bit engine.
HOST_F32T32   = $(OBP_WORK)/obp/os/sun/sparc/f32t32.dic
HOST_TOKENIZE = $(OBP_WORK)/obp/pkg/tokenizr/sparc/tokenize.dic

MKFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TOOLS_DIR  := $(MKFILE_DIR)tools
INNER_MK   := $(MKFILE_DIR)obp-gnu-inner.mk
FORTH64   := env QEMU_SPARC64=$(QEMU_SPARC64) FORTH64_BIN=$(FORTH64_BIN) $(TOOLS_DIR)/forth64.sh
FORTH32   := env QEMU_SPARC32=$(QEMU_SPARC32) FORTH32_BIN=$(FORTH32_BIN) $(TOOLS_DIR)/forth32.sh
MAKEDI    := env QEMU_SPARC64=$(QEMU_SPARC64) MAKEDI_SPARC_BIN=$(MAKEDI_SPARC_BIN) $(TOOLS_DIR)/makedi.sh
MAKEPROM  := env QEMU_SPARC64=$(QEMU_SPARC64) MAKEPROM_SPARC_BIN=$(MAKEPROM_SPARC_BIN) $(TOOLS_DIR)/makeprom.sh
DECOMPSIZE_SH := $(TOOLS_DIR)/decomp-size.sh
BOOTSTRAP := env QEMU_SPARC32=$(QEMU_SPARC32) FORTH32_BIN=$(FORTH32_BIN) $(TOOLS_DIR)/bootstrap-dics.sh
# Sun's TOKENIZE and FORTHTOOL (forth.mk:75-79): the 32-bit engine on the
# bootstrapped dictionaries, -D SUN4V from the platform flags.
TOKENIZE   = $(FORTH32) -d $(HOST_TOKENIZE) -D tokenizer? -D SUN4V
FORTHTOOL  = $(FORTH32) -d $(HOST_F32T32) -D SUN4V -s ""

PATCHES_DIR ?= $(REPO)/patches/obp/forth
# The four patches build/obp.mk applies to a working copy before building --
# reused unchanged, matching build/obp.mk's own recipe.
OBP_PATCHES := ophir-qemu-e1000.patch ide-srst-no-bsy-check.patch \
               md-iodevice-reg-guard.patch ophir-skip-eeprom-mac-sync.patch

OUTDIR ?= $(REPO)/output
OBP_WORK := $(OUTDIR)/_tmp/obp-gnu/$(OBP_PLATFORM)-$(OBP_TARGET)
OBP_BLD  := $(OBP_WORK)/obp/arch/sun4v/$(OBP_PLATFORM)/$(OBP_TARGET)

# The engine's expand_name() reads BP via getenv(), not just -D -- confirmed
# by building. BP is the obp *source* root (fm/, dev/, pkg/ all live directly
# under it), not the per-platform build directory.
BP := $(OBP_WORK)/obp
export BP

.PHONY: obp-gnu obp-gnu-clean

obp-gnu: $(OUTDIR)/openboot.bin

# --------------------------------------------------- scratch tree + patch --
# Never point BP at the real checkout: the dictionary bootstrap writes into
# it, and pkg/tokenizr/sparc/loadtok.fth saves to a BP-relative path Sun
# hardcoded rather than parameterized -- discovered the hard way
# when a first attempt silently overwrote the checked-in tokenize.dic. Always build in a copy, exactly as
# build/obp.mk already does for the Sun-toolchain path.
$(OBP_WORK)/.patched: | $(OUTDIR)
	rm -rf $(OBP_WORK)
	mkdir -p $(OBP_WORK)
	cp -Rp $(OBP_SRC) $(OBP_WORK)/obp
	$(foreach p,$(OBP_PATCHES),patch -s -p1 -d $(OBP_WORK) < $(PATCHES_DIR)/$(p) &&) true
	touch $@

$(OUTDIR):
	mkdir -p $(OUTDIR)

# ------------------------------------------------- dictionary bootstrap --
# Every dictionary the build loads -- k64t32.dic (bootprom.bin is built on
# it), f32t32.dic (FORTHTOOL: fonts, logo) and tokenize.dic (TOKENIZE: every
# dropin) -- is made here from the one shipped root, os/sun/sparc/forth.dic,
# by Sun's own steps on the 32-bit engine: the same chain the sun path runs
# on every build. The shipped copies in the build tree are deleted first and
# never read. Result: identical to Sun's for every kernel and listing, host
# dictionaries up to engine addresses (TESTS, dic-kernels/dic-host). ~6 s.
$(OBP_WORK)/.dictionaries: $(OBP_WORK)/.patched
	$(BOOTSTRAP) $(OBP_WORK)/obp
	touch $@

# ------------------------------------------------------------ dropin list --
# didepend runs native (text-processing only, no byte-order issue).
# arch/common.mk defaults DROPIN_SRC to ${PLATFORM}/release/dropins.src and
# no Makefile in the tree ever sets DROPINSRC, so a target-specific
# dropins.src (e.g. niagara/t1_fpga/dropins.src) is dead code Sun's own
# build never reads either -- measured against Sun's own build trace.
# Always use the platform's release/ directory, matching real behaviour.
#
# didepend's own output is left byte-for-byte as generated -- bare,
# cwd-relative filenames and all -- because obp-gnu-inner.mk consumes it via
# a sub-make run with -C $(OBP_BLD) (see header note); no path rewriting.
DROPINS_SRC := $(OBP_WORK)/obp/arch/sun4v/$(OBP_PLATFORM)/release/dropins.src
$(OBP_BLD)/builtin.fth $(OBP_BLD)/dropins.mk &: $(OBP_WORK)/.patched
	cd $(OBP_BLD) && \
	$(DIDEPEND_BIN) -D SUN4V -c $(DROPINS_SRC) > builtin.fth
	cd $(OBP_BLD) && \
	$(DIDEPEND_BIN) -D SUN4V -d $(DROPINS_SRC) > dropins.mk
	# The one dmake-ism didepend passes through verbatim: `buildoptions
	# X:= VAR += v` (dropins.src) becomes the line `X:=<ws>VAR += v`, dmake's
	# target-specific macro. GNU make would read that as assigning a variable
	# *named* X and silently drop it -- which is exactly what happened to
	# vpci.fc's `[define] 64BIT-ASSIGNED?` until 2026-09-20. Rewritten to GNU
	# make's equivalent `X: VAR += v`; this is the plan's
	# "target := VAR += x -> target-specific variables" item. Nothing else
	# in didepend's output uses `:=`.
	sed -i -E 's/^([^[:space:]:=]+):=[[:space:]]*/\1: /' $(OBP_BLD)/dropins.mk
	echo "" >> $(OBP_BLD)/dropins.mk
	echo "builtin.di: `cd $(OBP_BLD) && $(DIDEPEND_BIN) -D SUN4V -t $(DROPINS_SRC)`" \
	    >> $(OBP_BLD)/dropins.mk

# --------------------------------------------------------------- bootprom --
# Which loadprom.fth / reset.fth: resolved the way Sun's make does, from the
# target's own release Makefile -- RESET = ..., LOADFILE = ... if set, else
# ${PLATFORM}/loadprom.fth (arch/common.mk:149-151 LOADPROM). So niagara1-hw
# gets niagara/loadprom.fth (it has none of its own and says so), niagara
# its own, niagara2 its own niagara2/loadprom.fth -- a hardcoded niagara/
# path was right for the first two and wrong for the third.
REL_MK      := $(OBP_SRC)/arch/sun4v/$(OBP_PLATFORM)/$(OBP_TARGET)/Makefile
mkval        = $(strip $(shell sed -n 's/^$(1)[[:space:]]*=[[:space:]]*//p' $(REL_MK)))
SUN4V_DIR   := $(OBP_WORK)/obp/arch/sun4v
PLATFORM_DIR:= $(subst $${SUN4V},$(SUN4V_DIR),$(call mkval,PLATFORM))
mkpath       = $(subst $${PLATFORM},$(PLATFORM_DIR),$(subst $${SUN4V},$(SUN4V_DIR),$(1)))
LOADFILE_DECL := $(call mkval,LOADFILE)
BOOTPROM_LOADFILE := $(if $(LOADFILE_DECL),$(call mkpath,$(LOADFILE_DECL)),$(PLATFORM_DIR)/loadprom.fth)
RESET_LOADFILE     := $(call mkpath,$(call mkval,RESET))
$(OBP_BLD)/bootprom.bin $(OBP_BLD)/stand.dic &: $(OBP_WORK)/.dictionaries $(OBP_BLD)/version.fth $(OBP_BLD)/builtin.fth
	cd $(OBP_BLD) && $(FORTH64) -e 800 \
	    -d $(OBP_BLD)/../../../../../obp/fm/kernel/sparc/k64t32.dic -D SUN4V \
	    -D kernel-hdr-file=$(OBP_BLD)/../../../../../obp/fm/kernel/sparc/k64t32.fth \
	    -D LOADFILE=$(BOOTPROM_LOADFILE) \
	    -D SAVEFILE=bootprom.bin \
	    $(OBP_BLD)/../../../../../obp/arch/preload.fth

# The mixed link (TESTS, Appendix A): with REFERENCE_DIR set to a captured
# Sun-toolchain build directory (its niagara1-hw/release subtree),
# decomp.o, version.fth and revlevel are taken
# from there instead of being built/generated. Everything else -- engines,
# the bootstrapped dictionaries, every tokenized dropin, stand.dic, reset.o, the GNU link, makedi,
# makeprom -- stays ours. That removes the C compiler and the build stamp
# from the comparison, so any remaining difference in reset.bin is the GNU
# chain's own. Unset = the normal build.
REFERENCE_DIR ?=
ifneq ($(REFERENCE_DIR),)
$(OBP_BLD)/version.fth: $(REFERENCE_DIR)/version.fth $(REFERENCE_DIR)/revlevel $(OBP_WORK)/.patched
	cp -p $(REFERENCE_DIR)/version.fth $@
	cp -p $(REFERENCE_DIR)/revlevel $(OBP_BLD)/revlevel

$(OBP_BLD)/decomp.o: $(REFERENCE_DIR)/decomp.o $(OBP_WORK)/.patched
	cp -p $< $@
else
# version.fth/revlevel: our own stamp, not a copied reference -- TESTS 5.4,
# the build-stamp class. COMMENT-driven SUBREL is Sun's own extension point
# (release.mk); reproduced here with the stamp's date and the git rev.
#
# The date comes from build/stamp.sh: SOURCE_DATE_EPOCH, else the commit
# date of a clean tree, in UTC -- so two builds of one commit give the same
# openboot.bin. It lands in three places, all from this one file:
# sub-release, compile-signature (/openprom version, sccs-id) and the OBP
# dropin's header (reset/common.fth save-obj).
#
# obp-release is the banner's "OpenBoot 4.x.build_122..." and /openprom
# version's "OBP 4.x.build_122..." -- what prtconf -V shows. Sun's
# firmware.rel has "4.x.build_122***PROTOTYPE BUILD***"; this path never
# reads it (obp-gnu.mk hand-generates version.fth instead of running
# common.mk's bootprom.bin recipe, so FIRMWAREREL:sh never runs). Ours keeps
# Sun's number and adds +qemu, plus the release on a v* tag:
# 4.x.build_122+qemu-0.1 (STAMP_OBP_RELEASE, shared with the sun path in
# build/obp.mk). Two constraints on any override:
#   - os/bootprom/release.fth splits it at the dots into major.minor.patch
#     for firmware-version (FCode) and the dropin header, so the "4.x."
#     prefix must stay: it is what makes those 4.0.0, as in Sun's build.
#   - the banner prints it in full, followed by memory and serial; at more
#     than ~25 characters that line passes 80 columns.
OBP_FIRMWAREREL ?=
$(OBP_BLD)/version.fth: $(OBP_WORK)/.patched
	@eval "`$(REPO)/build/stamp.sh $(REPO)`"; \
	REL='$(OBP_FIRMWAREREL)'; \
	[ -n "$$REL" ] || REL=$$STAMP_OBP_RELEASE; \
	{ echo "headerless"; \
	  echo "$$STAMP_TD"; \
	  echo "constant compile-signature"; \
	  echo "create (sub-release ,\" [ sun4v-qemu-kit $$STAMP_MDY_HM git $$STAMP_REV #0]\""; \
	  echo "create (obp-release ,\" $$REL\""; \
	  echo "' (sub-release is sub-release"; \
	  echo "' (obp-release is obp-release"; \
	  echo "headers"; \
	} > $@
	echo 0 > $(OBP_BLD)/revlevel

# -------------------------------------------------------------- decomp.o --
DECOMP_SRC := $(REPO)/src/obp/tools/decomp.c
# -fno-pic -fno-pie: Debian's cross gcc is built --enable-default-pie, which adds a __sparc_get_pc_thunk section that
# decomp-size.sh does not count, and reset.bin then comes out longer than its header declares (pad-reset-bin.sh refuses).
# Sun builds decomp.o without PIC; Ubuntu's gcc defaults to non-PIC, so nothing changes there.
$(OBP_BLD)/decomp.o: $(DECOMP_SRC) $(OBP_WORK)/.patched
	sparc64-linux-gnu-gcc $(GNU_CSTD) -m32 -mcpu=v8 -O2 -fcommon -ffreestanding -fno-pic -fno-pie \
	    -fno-builtin -fno-tree-loop-distribute-patterns -DSTANDALONE \
	    -c $(DECOMP_SRC) -o $@

endif

# -------------------------------------------------------- reset.o/.bin --
$(OBP_BLD)/headers: $(OBP_BLD)/bootprom.bin
# Solaris `sort +1` runs in the C locale; GNU sort under a UTF-8 locale
# collates differently and acfheaders came out 1,138 bytes off the reference's
# while headers was identical. LC_ALL=C makes it byte-identical (2026-09-20).
$(OBP_BLD)/acfheaders: $(OBP_BLD)/headers
	LC_ALL=C sort -k2 $< > $@
$(OBP_BLD)/headerless: $(OBP_BLD)/acfheaders
	grep headerless $< > $@

$(OBP_BLD)/reset.o: $(OBP_BLD)/stand.dic $(OBP_BLD)/decomp.o $(OBP_BLD)/headerless
	@DSIZE=`$(DECOMPSIZE_SH) $(OBP_BLD)/decomp.o`; \
	cd $(OBP_BLD) && $(FORTH64) -D dropin-mode -D TARGET-FILE=reset.o -D RESET \
	    -D LOADFILE=$(RESET_LOADFILE) \
	    -e 900 -d stand.dic -D SUN4V \
	    -s "d# $$DSIZE constant decomp-size" \
	    -s " warning off" headerless \
	    $(OBP_BLD)/../../../../../obp/arch/preload.fth

$(OBP_BLD)/reset.bin: $(OBP_BLD)/reset.o $(OBP_BLD)/decomp.o
	sparc64-linux-gnu-ld -m elf32_sparc -N -s -e reset --no-warn-execstack \
	    -T $(MKFILE_DIR)openboot.ld \
	    $(OBP_BLD)/reset.o $(OBP_BLD)/decomp.o -o $(OBP_BLD)/reset.elf
	sparc64-linux-gnu-objcopy -O binary $(OBP_BLD)/reset.elf $@
	rm -f $(OBP_BLD)/reset.elf
	sh $(REPO)/build/obp/pad-reset-bin.sh $@
	sh $(REPO)/build/obp/verify-dropin-chain.sh $@

# ------------------------------------------------------------- dropins --
# fonts.mk / logo.mk (pulled in through dropins.mk) carry Sun's real recipes
# for font.di / sun-logo.di, including running mkfonts.fth / mklogo.fth via
# ${FORTHTOOL}; they are used as-is (obp-gnu-inner.mk defines no competing
# rules), so TOOLS/FORTHTOOL must resolve for them, not just MAKEDI/TOKENIZE. ${TOOLS}/makedi is a bare prerequisite (not invoked, just
# checked for existence) -- give it a real file to point at.
$(ENGINE_OUT)/makedi: $(ENGINE_OUT)/makedi-sparc
	ln -sf makedi-sparc $@

$(OBP_BLD)/builtin.di: $(OBP_BLD)/dropins.mk $(OBP_BLD)/bootprom.bin $(ENGINE_OUT)/makedi
	$(MAKE) -C $(OBP_BLD) -f $(INNER_MK) builtin.di \
	    BP=$(OBP_WORK)/obp \
	    MAKEDI='$(MAKEDI)' \
	    TOKENIZE='$(TOKENIZE)' \
	    TOOLS=$(ENGINE_OUT) \
	    FORTHTOOL='$(FORTHTOOL)'

# --------------------------------------------------------------- final --
$(OUTDIR)/openboot.bin: $(OBP_BLD)/reset.bin $(OBP_BLD)/builtin.di
	$(MAKEPROM) -o $@ -n $(OBP_BLD)/reset.bin $(OBP_BLD)/builtin.di
	sh $(REPO)/build/obp/verify-dropin-chain.sh $@

obp-gnu-clean:
	rm -rf $(OBP_WORK) $(OUTDIR)/openboot.bin
