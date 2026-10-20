# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# md -- the machine descriptions: 1up-md.bin (guest) and 1up-hv.bin (hv).
#
#   make md                 legion: bare Legion devices, no PCI
#   make md TARGET=pci   PCIe root complex and its devaliases
#
# Sources are md/$(TARGET)/1up.{pdesc,hdesc}, each a complete, self-contained
# machine -- no #ifdef branching between them. md/common.{pdesc,hdesc} holds only
# shared macros and constants, not conditional content. The two variants overlap
# on purpose, the same way Sun's own configs do: a change meant for both has to
# be made twice. See md/README. The compiler is a separate component,
# build/mdtools.mk -- a dependency here, not part of this file.
#
# TARGET names the directory; config.mk discovers which directories exist
# (any md/<target>/ with a 1up.pdesc) rather than listing names itself.
# Selecting the variant is done entirely by which directory gets compiled --
# there is no CONFIG_PCI or equivalent -D flag standing in for that choice;
# only MD_MEMSIZE, MD_TYPE and BANNER_NAME are ever passed to cpp (below).
#
# MD_LEGION_IO/MD_PCI (set in each md/<target>/config.mk) never reach cpp
# at all. They exist only for `make config`'s output and the MD_STAMP
# signature below. They derive from TARGET, same as the directory does, so
# they cannot drift from it.
#
# Only the no-PCI blob boots on unpatched upstream QEMU.
#
# Guest RAM in MB must match QEMU's -m. Nothing checks that, and a
# disagreement is not diagnosed by either side. It feeds both the guest MD's
# mblock size and the hv MD's memsize, which must agree with each other too.

MD_CPPFLAGS := -DMD_MEMSIZE=$(MD_MEM)M

# The md-type devalias, so `devalias` at the ok prompt records which MD the
# running firmware was built from. common.pdesc defaults it to "unknown",
# which is what shipped until 2026-08-28 because nothing passed this.
MD_CPPFLAGS += -DMD_TYPE='"$(TARGET)"'

# MD_SET names the strand configuration: md/<target>/$(MD_SET).pdesc and .hdesc are compiled into
# $(MD_SET)-md.bin and $(MD_SET)-hv.bin. Only 1up exists (QEMU's niagara machine has one CPU).
MD_SET ?= 1up

# The banner's first line, so a booting machine states its own configuration.
# Built here rather than in the .pdesc: traditional cpp can substitute inside
# string literals, but relying on that is a trick, and make can hand over the
# finished string. Position is fixed by OBP -- banner.fth types this, then
# ", <keyboard type>" -- so it cannot move without patching src/obp.
BANNER_NAME ?= Sun Fire T2000 [$(MD_SET)-md.bin: $(TARGET), $(MD_MEM)MB]
MD_CPPFLAGS += -DBANNER_NAME='"$(BANNER_NAME)"'

MDGEN_BIN ?= $(WORKDIR)/mdtools/mdgen

# A stamp recording what the blobs in $(OUTDIR) were built with, so a change
# rebuilds them. make has no dependency on a variable's value: without this,
# `make md TARGET=pci` after a legion build leaves the legion blob in place,
# and the -L directory looks complete while describing the wrong machine.
#
# It stores the VALUES, not $(MD_CPPFLAGS). That string carries the quoting the
# -D flags need, which breaks a shell comparison. The values have no quotes.
#
# ANYTHING NEW THAT CHANGES THE BLOBS MUST BE ADDED HERE. A variable left out
# fails to trigger a rebuild, which is exactly what this stamp prevents.
MD_SIGNATURE := $(TARGET)|$(MD_LEGION_IO)|$(MD_PCI)|$(MD_MEM)|$(BANNER_NAME)
MD_STAMP := $(OUTDIR)/.md-signature

# One OUTDIR, one machine (build/set-ok.sh): a component built for another TARGET into a set that is there would mix two machines,
# and `make install` would take the mixture for a complete set. `all` and `clean` start from nothing, so they are not asked.
ifneq ($(TARGET),all)
ifeq ($(filter all clean distclean,$(MAKECMDGOALS)),)
ifneq ($(filter md hv_reset obp obp-gnu obp-build,$(MAKECMDGOALS)),)
# --stamp writes OUTDIR/.md-signature: not in a dry run (make -n)
_SET_MSG := $(shell sh build/set-ok.sh '$(OUTDIR)' '$(TARGET)' $(if $(or $(filter md,$(MAKECMDGOALS)),$(_DRY_RUN)),,--stamp))
$(if $(_SET_MSG),$(error $(_SET_MSG)))
endif
ifneq ($(filter install,$(MAKECMDGOALS)),)
_SET_MSG := $(shell sh build/set-ok.sh '$(OUTDIR)' '$(TARGET)' '$(MD_SIGNATURE)')
$(if $(_SET_MSG),$(error $(_SET_MSG)))
endif
endif
endif

.PHONY: md md-clean md-verify md-verify-reference boot-verify workdir-verify guards-verify tools-verify login-verify sun-verify sun-login-verify headers-check test test-all test-full tests-full FORCE-MD

md: $(OUTDIR)/$(MD_SET)-md.bin $(OUTDIR)/$(MD_SET)-hv.bin

$(MD_STAMP): FORCE-MD
	@mkdir -p $(OUTDIR)
	@if [ ! -f $@ ] || [ "`cat $@ 2>/dev/null`" != "$(MD_SIGNATURE)" ]; then echo "$(MD_SIGNATURE)" > $@; fi

FORCE-MD:

$(OUTDIR)/$(MD_SET)-md.bin: md/$(TARGET)/$(MD_SET).pdesc md/common.pdesc $(MD_STAMP) | mdtools
	@mkdir -p $(OUTDIR) $(WORKDIR)/mdtools
	$(MD_CPP) $(MD_CPPFLAGS) md/$(TARGET)/$(MD_SET).pdesc $(OUTDIR)/$(MD_SET)-md.pp
	$(MDGEN_BIN) --binary --outfile $@ $(OUTDIR)/$(MD_SET)-md.pp
	$(MDGEN_BIN) --text   --outfile $(WORKDIR)/mdtools/$(MD_SET)-md.txt $(OUTDIR)/$(MD_SET)-md.pp
	@rm -f $(OUTDIR)/$(MD_SET)-md.pp
	@echo "$(MD_SET)-md.bin -> $@  (TARGET=$(TARGET))"

$(OUTDIR)/$(MD_SET)-hv.bin: md/$(TARGET)/$(MD_SET).hdesc md/common.hdesc $(MD_STAMP) | mdtools
	@mkdir -p $(OUTDIR) $(WORKDIR)/mdtools
	$(MD_CPP) $(MD_CPPFLAGS) md/$(TARGET)/$(MD_SET).hdesc $(OUTDIR)/$(MD_SET)-hv.pp
	$(MDGEN_BIN) --binary --outfile $@ $(OUTDIR)/$(MD_SET)-hv.pp
	$(MDGEN_BIN) --text   --outfile $(WORKDIR)/mdtools/$(MD_SET)-hv.txt $(OUTDIR)/$(MD_SET)-hv.pp
	@rm -f $(OUTDIR)/$(MD_SET)-hv.pp
	@echo "$(MD_SET)-hv.bin -> $@  (TARGET=$(TARGET))"

md-clean:
	rm -f $(MD_STAMP) $(OUTDIR)/$(MD_SET)-md.bin $(WORKDIR)/mdtools/$(MD_SET)-md.txt \
	      $(OUTDIR)/$(MD_SET)-hv.bin $(WORKDIR)/mdtools/$(MD_SET)-hv.txt

# The MD gate (tests/full/md/README): every config under md/ builds deterministically, unfolds to mdgen source and refolds to the
# same bytes through mdlint, its graph is well formed (fwd/back paired, FWARC 2005/115), and the blobs match
# tests/full/md/expected/blobs.sha256. It builds every config itself into a scratch directory, so TARGET and OUTDIR are
# not used (its scratch directory is $(WORKDIR)/md-test); about 12 s, no QEMU. `md-verify-reference` adds Sun's T1 comparison (needs the T1 tree, T1=).
md-verify:
	@rm -rf '$(WORKDIR)/md-test'; OUTDIR='$(WORKDIR)/md-test' tests/lib/gate.sh md tests/full/md/run

md-verify-reference:
	@rm -rf '$(WORKDIR)/md-test'; OUTDIR='$(WORKDIR)/md-test' tests/lib/gate.sh md-ref tests/full/md/run reference

# The boot gate (tests/full/boot/README): legion's full firmware set booted to the OpenBoot prompt under the distribution's QEMU,
# device tree and properties compared with tests/full/boot/expected/legion.obp. 1-2 minutes; builds its own firmware, so
# TARGET and OUTDIR are not used. No Solaris.
boot-verify:
	@rm -rf '$(WORKDIR)/boot-test'; OUTDIR='$(WORKDIR)/boot-test' tests/lib/gate.sh boot tests/full/boot/run

# The work directory gate (tests/full/workdir/run): build/workdir.sh makes a directory with a marker and removes only a
# directory that carries it. No build, no QEMU, a second or two.
workdir-verify:
	tests/lib/gate.sh workdir tests/full/workdir/run

# The guards gate (tests/full/guards/run): what the Makefile refuses before it builds (MD_MEM, a space in a path, a moved tree, a
# second machine or a second make in one OUTDIR, the wrong toolchain for the host).
guards-verify:
	tests/lib/gate.sh guards tests/full/guards/run

# The tools gate (tests/full/tools/run): tests/lib/gate.sh and tests/run-all on a gate that exits 0 with a FAIL line, and the md/ bundle of
# a release (build/pack-md.sh) on a list too long for one xargs run. No build, no QEMU, a few seconds.
tools-verify:
	tests/lib/gate.sh tools tests/full/tools/run

# The login gate (tests/full/login/README): legion's firmware set booted all the way to Solaris's `console login:` from a guest disk
# that is not in this repository (GUEST_DISK=<image>; without it the gate is skipped, exit 3). About a minute. Part of test-full only
# when GUEST_DISK is set.
login-verify:
	@rm -rf '$(WORKDIR)/login-test'; OUTDIR='$(WORKDIR)/login-test' tests/lib/gate.sh login tests/full/login/run

# The sun-path gate (tests/sun/README): on Solaris, TOOLCHAIN=sun builds the MDs and the hypervisor and checks them (the MD hashes
# against the pins the gnu path is held to; q.bin carries no build directory). The other gates do not run on the sun path.
sun-verify:
	@rm -rf '$(WORKDIR)/sun-test'; OUTDIR='$(WORKDIR)/sun-test' tests/lib/gate.sh sun tests/sun/run

# Sun-built sets (a sun-path build runs on Solaris, no QEMU there) booted to the login prompt on a Linux host, one per compiler:
# `make sun-login-verify SETS="DIR..." GUEST_DISK=<image>` (tests/sun/README). Not part of test-all.
sun-login-verify:
	@tests/lib/gate.sh sun-login tests/sun/login-sets $(SETS)

# Every script and makefile of this project's own layer carries the BSD-2-Clause header (scripts/check-headers.sh; --fix adds a missing one).
headers-check:
	@scripts/check-headers.sh

# `make test`: the shortest check. Builds legion's firmware set from this tree (cached by a hash of the tree: an unchanged tree is not
# rebuilt), boots it under the distribution QEMU and checks the OpenBoot banner and its ok prompt (tests/smoke/README). About 2 seconds
# when the set is cached, about 25 seconds after a change. `make test-all` (aliases test-full, tests-full) is everything in tests/full on top of
# that: md-verify, boot-verify, hv-verify, obp-verify. The Sun comparison (md-verify-reference) needs the T1 tree and stays separate.
ifeq ($(TOOLCHAIN),sun)
test:
	@echo 'make test builds on the `gnu` path and boots the set under QEMU. On the `sun` path it runs `gmake sun-verify` (selected automatically).'
	@$(MAKE) sun-verify
else
test:
	@SMOKE_CACHE='$(WORKDIR)/smoke' tests/lib/gate.sh smoke tests/smoke/run --build
endif

# `make test-all` (aliases test-full, tests-full): every gate in turn through tests/run-all, one result line each and a table at the end
# (PASS / FAIL / SKIP, checks, time); login-verify joins when GUEST_DISK is set. Exit code 1 if a gate failed.
ifeq ($(TOOLCHAIN),sun)
test-all test-full tests-full:
	@echo 'make test-all runs the gates of the `gnu` path (QEMU, python3). On the `sun` path it runs `gmake sun-verify` (selected automatically).'
	@$(MAKE) sun-verify
else
test-all test-full tests-full:
	@rm -rf '$(WORKDIR)/test-all'; OUT='$(WORKDIR)/test-all' WORKDIR='$(WORKDIR)' tests/run-all
endif
