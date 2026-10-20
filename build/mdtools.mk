# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# mdtools -- the sun4v Machine Description compiler and linter: mdgen, mdlint.
#
#   make mdtools                  # auto-detected toolchain
#   make mdtools TOOLCHAIN=sun    # Sun Studio on Solaris
#   make mdtools TOOLCHAIN=gnu    # gcc, any host
#
# A component in its own right, unrelated to the hypervisor. These are the
# tools that compile md/*.pdesc into blobs. Someone who only wants to change a
# machine description needs md/ and md.mk, and this only as the compiler.
#
# Continues github.com/unix0cc/mdbuild, the earlier version (its own repo).
#
# Built from src/hypervisor/src/support/{mdgen,mdlint}, which the pristine
# import already carries. Both toolchains work. No submodule, no external repo.
#
# The gnu path applies patches/mdtools/gnu/mdgen-mdlint-host-endian.patch to a copy of
# the sources -- a little-endian arm for the byte-order macros (Sun's #else is
# just #error), plus one hton64() Sun forgot. src/ is not modified either way.
#
# There is no build/mdtools/sun/: the sun path is a call into Sun's makefiles
# and fits in the recipe below. Same asymmetry as build/hv_reset.mk.
#
# Sun's Makefile hardcodes LEX to /pkg/gnu/bin, an internal path. Resolve
# through PATH instead of naming /usr/sfw/bin (flex is SUNWflexlex, part of the
# Solaris 10 distribution; see config.mk for what was checked).

MD_SRC    := src/hypervisor
MD_WORK   := $(WORKDIR)/md-build
MD_OUTDIR := $(WORKDIR)/mdtools

.PHONY: mdtools mdtools-clean

ifeq ($(TOOLCHAIN),sun)

# Sun's makefiles build in place, so copy the tree out first. The copy lands in
# $(WORKDIR), never in the repo.
mdtools:
	@[ -x "$(SUN_STUDIO)/bin/cc" ] || { echo "no cc at $(SUN_STUDIO)/bin/cc -- set SUN_STUDIO=" >&2; exit 2; }
	@[ -x "$(MAKE_SUN)" ] || { echo "$(MAKE_SUN) not found -- need the SysV make, not gmake" >&2; exit 2; }
	@PATH=$(SUN_PATH); export PATH; $(FLEX) --version >/dev/null 2>&1 || { \
	    echo "$(FLEX) not runnable on $(SUN_PATH) -- set FLEX=/path/to/flex" >&2; exit 2; }
	rm -rf $(MD_WORK)
	@mkdir -p $(dir $(MD_WORK))
	cp -Rp $(MD_SRC) $(MD_WORK)
	cd $(MD_WORK)/src/support/mdgen  && PATH=$(SUN_PATH) SUN_STUDIO=$(SUN_STUDIO) $(MAKE_SUN) mdgen LEX=$(FLEX)
	cd $(MD_WORK)/src/support/mdlint && PATH=$(SUN_PATH) SUN_STUDIO=$(SUN_STUDIO) $(MAKE_SUN)
	@mkdir -p $(MD_OUTDIR)
	cp $(MD_WORK)/src/support/mdgen/mdgen $(MD_WORK)/src/support/mdlint/mdlint $(MD_OUTDIR)/
	@echo "mdgen, mdlint -> $(MD_OUTDIR)/"

else

mdtools:
	@$(FLEX) --version >/dev/null 2>&1 || { echo "$(FLEX) not runnable -- set FLEX=/path/to/flex" >&2; exit 2; }
	@mkdir -p $(MD_OUTDIR)
	CC="$(HOST_GCC) $(HOST_CSTD)" FLEX=$(FLEX) sh build/mdtools/gnu/build.sh $(MD_SRC)/src $(MD_WORK) $(CURDIR)/patches/mdtools/gnu/mdgen-mdlint-host-endian.patch
	cp $(MD_WORK)/mdgen $(MD_WORK)/mdlint $(MD_OUTDIR)/
	@echo "mdgen, mdlint -> $(MD_OUTDIR)/"

endif

mdtools-clean:
	rm -rf $(MD_WORK) $(MD_OUTDIR)
