# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# sun4v-qemu-kit -- OpenSPARC T1 firmware for QEMU's -M niagara.
#
# `make` builds the complete ROM set into one -L directory. Components:
#
#   make hv_reset  reset.bin, q.bin
#   make obp       openboot.bin
#   make md        1up-md.bin, 1up-hv.bin
#   make nvram     nvram1
#   make mdtools   mdgen, mdlint  (a tool, not firmware; md needs it)
#
# Checks (gnu path only, no Sun host needed):
#   make obp-verify   openboot.bin against Sun's own images   (tests/full/obp/TESTS)
#   make hv-verify    q.bin/reset.bin build: GNU as vs Sun as (tests/full/hv_reset/README)
#   make check        the same as make test
#   make distclean    clean, and remove what ./configure wrote
#   make dist         the same as make release
#   make test         legion set built and booted to the OpenBoot banner + ok prompt, about 2 s when the tree is unchanged (tests/smoke/README)
#   make test-all    test + everything in tests/full, one PASS/FAIL line per gate and a table (tests/run-all; also: make test-full, tests-full)
#   make release      firmware tarball from a clean commit; make release-check builds it twice and compares (build/release.sh)
#   make bootstrap-check   OBP seed derived from source with cforth and compared with Sun's files in src/ (forth_bootstrap/README; also bootstrap-chain, bootstrap-negative)
#   make install      copy a built set to $(prefix)/share/sun4v-qemu-kit/<TARGET>/ (--prefix, DESTDIR; see "Installing" below)
#   make md-verify    every md/ config: refold hashes, mdlint, graph, pinned blobs (tests/full/md/README)
#   make boot-verify  legion firmware set booted to OpenBoot under the distro QEMU, tree + properties (tests/full/boot/README)
#   make login-verify legion booted to Solaris's login prompt from GUEST_DISK=<image> (skipped without it; tests/full/login/README); in test-full when GUEST_DISK is set
#   make sun-verify   on Solaris with TOOLCHAIN=sun: the sun-built MDs against the pinned hashes, q.bin without the build directory (tests/sun/README)
#
# TOOLCHAIN picks how reset.bin/q.bin and openboot.bin are built:
#   sun  Sun's unmodified Makefile.master chain. Needs Solaris, Sun Studio 11
#        and a patched /usr/ccs/bin/as (REQUIREMENTS.SOLARIS). stabs and aschk
#        are built from source. Nothing prebuilt is used.
#   gnu  sparc64-linux-gnu-{gcc,as,ld,objcopy}. No Sun software. openboot.bin
#        additionally needs the -m32 multilib and qemu-sparc64 +
#        qemu-sparc32plus linux-user emulators (QEMU_SPARC64/QEMU_SPARC32 in
#        config.mk) to run the cross-built 64- and 32-bit Forth engines.
#
# Auto-detected from `uname -s`. Override with `make TOOLCHAIN=gnu`.
#
# On Solaris invoke this as `gmake`: it needs GNU make (ifeq, $(shell ...)).
# The Sun makefiles it shells out to need /usr/ccs/bin/make instead, so a
# sun-path build uses both. /usr/ccs/bin/make stops at the GUARD line below
# (its :sh macro runs at once; GNU make reads it as a target variable and
# ignores it) and says to use gmake.
#
# Output goes to $(OUTDIR): <checkout>/output by default (config.mk: a CANONICAL_TREE builds
# to ~/build/sun4v-qemu-kit/<toolchain> instead). The
# repo holds source and build scripts only, never intermediate state. Override
# with `make OUTDIR=...`. See config.mk.
#
# TARGET picks the machine: any md/<target>/ that has a 1up.pdesc (`legion`
# is the default; config.mk discovers the rest, no name list anywhere).
# TARGET=all builds every one of them, each into $(OUTDIR)/<target>,
# forwarding whatever goal you asked for.

GUARD:sh = echo 'This Makefile needs GNU make: run `gmake`, not `make`.' >&2; exit 1

.DEFAULT_GOAL := all
.PHONY: all

include config.mk

# The sun path runs Sun's own tools and makefiles: it builds on Solaris only. Said at once, before `clean` (a prerequisite of `all`)
# has removed OUTDIR and before the first tool is looked for in /opt/SUNWspro.
ifneq ($(filter all hv_reset obp obp-gnu obp-build md mdtools install,$(or $(MAKECMDGOALS),all)),)
ifeq ($(TOOLCHAIN),sun)
ifneq ($(UNAME_S),SunOS)
$(error TOOLCHAIN=sun builds on Solaris only; this host is $(UNAME_S). Use TOOLCHAIN=gnu (README.configure))
endif
endif
ifeq ($(TOOLCHAIN),gnu)
ifeq ($(UNAME_S),SunOS)
$(error TOOLCHAIN=gnu needs the sparc64-linux-gnu cross toolchain and qemu-user, a Linux host; on Solaris use TOOLCHAIN=sun (REQUIREMENTS.SOLARIS))
endif
endif
endif

# The gates of the gnu path need QEMU, python3, the cross toolchain; on the sun path the one gate is sun-verify.
GNU_GOALS := md-verify md-verify-reference boot-verify login-verify obp-verify obp-test obp-test-external hv-verify hv-test \
             bootstrap-check bootstrap-chain bootstrap-negative
ifeq ($(TOOLCHAIN),sun)
ifneq ($(filter $(GNU_GOALS),$(MAKECMDGOALS)),)
$(error $(filter $(GNU_GOALS),$(MAKECMDGOALS)) checks the `gnu` path (QEMU, python3, the cross toolchain). On the `sun` path use `gmake sun-verify`)
endif
endif

# ---------------------------------------------------------------------------
# TARGET=all -- build every configuration under md/ in one pass.
#
# --no-print-directory keeps the recursion quiet, but GNU make also puts it into MAKEFLAGS, and Solaris' make reads MAKEFLAGS letter by
# letter: its `o` takes an argument ("No dmake output dir argument after -o flag"), so the sun path does without it.
NPD := $(if $(filter sun,$(TOOLCHAIN)),,--no-print-directory)
# A configuration is any md/<target>/ that holds a 1up.pdesc. Each is built into
# its own $(OUTDIR)/<target> by re-invoking make once per config, so every
# TARGET-coupled default in config.mk (the OBP target, the MD flags, the
# banner) resolves exactly as for a direct `make TARGET=<target>`.
#
# Whatever goals you pass are forwarded unchanged:
#   make TARGET=all              -> `all`    for each config
#   make config TARGET=all       -> `config` for each config
#   make clean  TARGET=all       -> `clean`  for each config  ($(OUTDIR)/<target>)
#
# TARGETS is config.mk's own discovery (it needs it too, to validate a
# non-'all' TARGET); reused here rather than recomputed.

# A dry run (make -n) judges the lock and the work directory but makes neither.
_DRY_RUN := $(findstring n,$(firstword $(filter-out --%,$(MAKEFLAGS))))

ifeq ($(TARGET),all)

_MD_ALL_GOALS := $(or $(MAKECMDGOALS),$(.DEFAULT_GOAL))

# `make -jN TARGET=all clean all` would run clean beside the build it is meant to precede
.NOTPARALLEL:

# One make at a time per OUTDIR here too (build/lock.sh, see below): the makes it starts per configuration work in directories of
# their own and take no lock, so this is the only place.
ifneq ($(filter 0 $(if $(filter command line,$(origin CONFIG_AUTO)),1),$(MAKELEVEL)),)
ifneq ($(filter-out config help print-%,$(_MD_ALL_GOALS)),)
_LOCK_MSG := $(shell sh build/lock.sh '$(WORKDIR)' $(if $(_DRY_RUN),check))
$(if $(_LOCK_MSG),$(error $(_LOCK_MSG)))
endif
endif

.PHONY: $(_MD_ALL_GOALS)
$(_MD_ALL_GOALS):
	@[ -n "$(TARGETS)" ] || { echo "TARGET=all: no md/*/1up.pdesc found" >&2; exit 2; }
	@# One work directory per target, inside the one that belongs to this OUTDIR.
	@case "$@" in clean|distclean|workdir-clean|config|help|print-*) ;; *) \
	    msg=`sh build/workdir.sh make '$(WORKDIR)' '$(CURDIR)' '$(OUTDIR)'`; \
	    if [ -n "$$msg" ]; then echo "$$msg" >&2; exit 2; fi ;; esac
	@set -e; for c in $(TARGETS); do \
	    printf '\n=== TARGET=%s   goal=%s   -> %s/%s ===\n' "$$c" "$@" "$(OUTDIR)" "$$c"; \
	    $(MAKE) $(NPD) TARGET="$$c" OUTDIR="$(OUTDIR)/$$c" WORKDIR="$(WORKDIR)/$$c" $@; \
	done
	@case "$@" in clean|distclean|workdir-clean) sh build/workdir.sh clean '$(WORKDIR)' '$(CURDIR)' ;; esac

else

include build/hv_reset/options.mk

# `make all OUTDIR=$PWD` would make clean remove the clone: refuse such an OUTDIR
# before anything runs (build/outdir-ok.sh). Not for config/help, which only print.
ifneq ($(filter-out config help,$(or $(MAKECMDGOALS),all)),)
_OUTDIR_MSG := $(shell sh build/outdir-ok.sh '$(OUTDIR)' '$(CURDIR)')
$(if $(_OUTDIR_MSG),$(error $(_OUTDIR_MSG)))
endif

# One make at a time per OUTDIR (build/lock.sh). It comes before the toolchain check below, which may remove OUTDIR: a make that is
# refused must not have touched it. `all` starts with `clean`, and two makes would wipe each other's work. Taken by the
# outermost make, or by the one a configure-written Makefile starts (it passes CONFIG_AUTO); the makes the build and the tests start
# themselves work in directories of their own. Not for goals that only print.
ifneq ($(filter all workdir hv_reset obp obp-gnu obp-build md mdtools clean distclean workdir-clean test test-all test-full tests-full check md-verify md-verify-reference boot-verify login-verify sun-verify obp-test obp-verify obp-test-external hv-test hv-verify,$(or $(MAKECMDGOALS),all)),)
ifneq ($(filter 0 $(if $(filter command line,$(origin CONFIG_AUTO)),1),$(MAKELEVEL)),)
_LOCK_MSG := $(shell sh build/lock.sh '$(WORKDIR)' $(if $(_DRY_RUN),check))
$(if $(_LOCK_MSG),$(error $(_LOCK_MSG)))
endif
endif

# gnu path: output of one set of tools is not reused by another (build/toolchain-check.sh). Only for the goals that build into OUTDIR (not
# install, release, the gates, headers-check, clean, config, help), and not for a goal that only prints (print-*) or a dry run (-n): the check removes OUTDIR when the tools changed, and runs while the Makefile
# is read, so `make -n` would delete the firmware set it was only asked to describe.
# PATH is passed on by hand: GNU make before 4.4 does not give $(shell) the PATH that config.auto.mk exports (--with-gcc-cross).
ifneq ($(TOOLCHAIN),sun)
ifneq ($(filter all hv_reset obp obp-gnu obp-build md mdtools nvram,$(or $(MAKECMDGOALS),all)),)
_TOOLCHAIN_CHECK_CMD = PATH='$(PATH)' sh build/toolchain-check.sh '$(OUTDIR)' '$(HOST_GCC)' '$(QEMU_SPARC64)' '$(QEMU_SPARC32)' '$(GNU_CSTD)' '$(HOST_CSTD)' '$(WORKDIR)' '$(CURDIR)'
ifeq ($(_DRY_RUN),)
_TOOLCHAIN_CHECK := $(shell $(_TOOLCHAIN_CHECK_CMD))
$(if $(_TOOLCHAIN_CHECK),$(info $(_TOOLCHAIN_CHECK)))
endif
endif
# `make all` starts with `clean`, which removes the record: write it again after that.
.PHONY: toolchain-record
toolchain-record:
	@$(_TOOLCHAIN_CHECK_CMD)
_TOOLCHAIN_RECORD := toolchain-record
endif


# The work directory is made (with its marker) before anything is built in it, and refused when it is not fit
# (build/workdir.sh): `/`, the home directory, the sources, OUTDIR, or a directory that is not empty and was not made by this build.
# Only for the goals that build or test in it (the gates keep their scratch directories and the smoke cache in it); `release` runs
# its own make, with its own OUTDIR and WORKDIR.
ifneq ($(filter all workdir hv_reset obp obp-gnu obp-build md mdtools obp-test obp-verify obp-test-external hv-test hv-verify test test-all test-full tests-full check md-verify md-verify-reference boot-verify login-verify sun-verify,$(or $(MAKECMDGOALS),all)),)
_WORKDIR_MSG := $(shell sh build/workdir.sh make '$(WORKDIR)' '$(CURDIR)' '$(OUTDIR)' $(if $(_DRY_RUN),check))
$(if $(_WORKDIR_MSG),$(error $(_WORKDIR_MSG)))
endif

# One include per component. Each dispatches on TOOLCHAIN internally where the
# paths differ.
include build/hv_reset.mk
include build/mdtools.mk

# openboot.bin. Both paths build it; the gnu one runs the Forth engine under
# qemu-sparc64/qemu-sparc32plus because the dictionary images are native
# SPARC code, and one of them (forth.dic) has no source of its own -- every
# other dictionary is bootstrapped from it. `make obp-verify` is the gnu
# path's equivalence gate against Sun's own images. See build/obp/README
# and tests/full/obp/TESTS.
include build/obp.mk

# The machine descriptions, from md/*.pdesc and md/*.hdesc. Edit those to
# change what the guest is told it has. build/mdtools.mk builds the compiler.
include build/md.mk

# nvram1 -- zeros. Nothing in this firmware reads it; QEMU only needs it to
# exist. See build/nvram/README.
include build/nvram.mk

# make release: the firmware tarball, from a clean commit. build/release.sh.
include build/release.mk

# make bootstrap-check / bootstrap-chain / bootstrap-negative: forth_bootstrap/.
include forth_bootstrap/forth_bootstrap.mk

# ---------------------------------------------------------------------------
# Cleaning.
#
#   make clean           everything
#   make hv_reset-clean  reset.bin/q.bin and their work tree
#   make obp-clean       openboot.bin and its work tree(s)
#   make md-clean        the MD blobs
#   make mdtools-clean   mdgen/mdlint
#   make nvram-clean     nvram1
#
# `clean` removes $(OUTDIR) wholesale, and $(WORKDIR) too when it carries the marker file
# the build put there (build/workdir.sh). Nothing else is written, and the repository is
# never touched.
.PHONY: clean workdir workdir-clean

# An OUTDIR that is, contains or holds the sources is refused at parse time
# (build/outdir-ok.sh), so this cannot delete the clone.
clean: workdir-clean
	rm -rf $(OUTDIR)
	@echo "removed $(OUTDIR)"
# only for `make clean` / `make distclean` themselves: a bare `make` has no goals, but runs `all`, whose clean must keep the lock
ifneq ($(MAKECMDGOALS),)
ifeq ($(filter-out clean distclean,$(MAKECMDGOALS)),)
	@rm -f '$(WORKDIR).lock'
endif
endif

# Only the work directory. `all` makes it again after `clean` has removed it.
workdir-clean:
	@sh build/workdir.sh clean '$(WORKDIR)' '$(CURDIR)'

workdir:
	@msg=`sh build/workdir.sh make '$(WORKDIR)' '$(CURDIR)' '$(OUTDIR)'`; \
	    if [ -n "$$msg" ]; then echo "$$msg" >&2; exit 2; fi

# `make print-WORKDIR` prints the value of one variable (./configure uses it).
print-%:
	@echo '$($*)'

# The names a GNU package answers to: check is `make test` (the smoke test; the
# full gates are test-all), distclean is clean plus what ./configure wrote, dist
# is `make release`.
.PHONY: check distclean dist

check: test

distclean: clean
	rm -f config.auto.mk config.status config.log
	rm -rf config.wrap
	rm -rf autom4te.cache
	@rmdir output 2>/dev/null || true

dist: release

# ---------------------------------------------------------------------------
# Every ROM file add_rom_or_fail() in hw/sparc64/niagara.c asks for.
FIRMWARE := reset.bin q.bin openboot.bin nvram1 1up-md.bin 1up-hv.bin

# `all` cleans first, always. TARGET and OBP_PLATFORM/OBP_TARGET are coupled
# in config.mk, and `obp` is PHONY with no dependency on TARGET's value. An
# incremental `all` after switching TARGET could leave a stale openboot.bin
# from the previous config in $(OUTDIR). `all` means "the whole matching set",
# so it pays for a full rebuild. Individual targets stay incremental.
# `all` starts with `clean`: under -jN it would run beside the build and remove what that builds. GNU make before 4.4 takes this line
# as "no parallelism in this Makefile"; 4.4 limits it to `all`. Nothing in the build uses -jN anyway (the OBP chain is sequential,
# the sun path's makes have no jobserver): -jN is accepted and has no effect.
.NOTPARALLEL: all
# OUTDIR as the user can type it: inside the checkout relative (a container sees /src, the host does not).
_OUTDIR_HINT = $(patsubst $(CURDIR)/%,./%,$(OUTDIR))

all: clean $(_TOOLCHAIN_RECORD) workdir hv_reset obp md nvram
	@echo
	@echo "firmware set in $(OUTDIR):"
	@missing=; for f in $(FIRMWARE); do \
	    case "$$f" in \
	        reset.bin)    desc="CPU reset vector -- bootstraps and hands off to the hypervisor" ;; \
	        q.bin)        desc="Hypervisor (hv) binary" ;; \
	        openboot.bin) desc="OpenBoot PROM (firmware/bootloader)" ;; \
	        nvram1)       desc="NVRAM stub (required by QEMU, unread by firmware)" ;; \
	        1up-md.bin)   desc="Guest MD (Machine Description) -- describes the domain to Solaris/OBP" ;; \
	        1up-hv.bin)   desc="Hypervisor MD (Machine Description) -- describes the platform to the hv itself" ;; \
	        *)            desc="" ;; \
	    esac; \
	    if [ -f "$(OUTDIR)/$$f" ]; then \
	        printf '  %-14s %8s bytes   %s\n' "$$f" "`wc -c < $(OUTDIR)/$$f | tr -d ' '`" "$$desc"; \
	    else \
	        printf '  %-14s %8s          %s\n' "$$f" "MISSING" "$$desc"; missing="$$missing $$f"; \
	    fi; \
	done; \
	if [ -n "$$missing" ]; then echo; echo "incomplete:$$missing" >&2; exit 1; fi
	@echo
	@echo "build done: $(words $(FIRMWARE)) files in $(_OUTDIR_HINT)"
	@echo "------------------------------------------------------------------------"
	@echo "boot with:"
	@echo "  qemu-system-sparc64 -M niagara -L $(_OUTDIR_HINT) -m $(MD_MEM) -nographic -serial mon:stdio"
ifeq ($(MD_LEGION_IO),yes)
	@echo
	@echo "Solaris disk from the T1 archive (disk.s10hw2); at the ok prompt type \"boot disk\":"
	@echo "  qemu-system-sparc64 -M niagara -L $(_OUTDIR_HINT) -m $(MD_MEM) -nographic -serial mon:stdio -drive if=pflash,file=<disk.s10hw2>,format=raw"
	@echo
	@echo "Solaris 10 1/13 DVD: ./configure --with-md-mem=1024, then see README.S10U11"
endif
	@echo
	@echo "quit QEMU: Ctrl-a x"
	@echo "------------------------------------------------------------------------"

# ---------------------------------------------------------------------------
# Installing a built set. Does not build: `all` cleans first and a full OBP build
# takes minutes, so an install that quietly rebuilt would be a surprise. It checks
# that $(OUTDIR) holds the whole set and stops with the command to run if not.
#
#   make all && make install                  -> $(pkgdatadir)/<TARGET>/
#   make install prefix=/opt/fw DESTDIR=/tmp/stage
#   make install TARGET=all                -> one subdirectory per configuration
#   make uninstall
#
# Then:  qemu-system-sparc64 -M niagara -L $(pkgdatadir)/<TARGET> -m <MD_MEM> ...
INSTALL_DOCS := README README.USAGE
INSTALL_DIR  = $(DESTDIR)$(pkgdatadir)/$(TARGET)

.PHONY: install uninstall

install:
	@missing=; for f in $(FIRMWARE); do [ -f "$(OUTDIR)/$$f" ] || missing="$$missing $$f"; done; \
	if [ -n "$$missing" ]; then \
	    echo "make install: $(OUTDIR) does not hold the whole set (missing:$$missing); build it first: make all TARGET=$(TARGET)" >&2; exit 1; \
	fi; \
	set -e; mkdir -p "$(INSTALL_DIR)" "$(DESTDIR)$(docdir)"; \
	for f in $(FIRMWARE); do cp "$(OUTDIR)/$$f" "$(INSTALL_DIR)/$$f"; chmod 644 "$(INSTALL_DIR)/$$f"; done; \
	for f in $(INSTALL_DOCS); do cp "$$f" "$(DESTDIR)$(docdir)/$$f"; chmod 644 "$(DESTDIR)$(docdir)/$$f"; done; \
	echo "installed $(TARGET) in $(INSTALL_DIR)"; \
	echo "boot with:  qemu-system-sparc64 -M niagara -L $(pkgdatadir)/$(TARGET) -m $(MD_MEM) -nographic -serial mon:stdio"

uninstall:
	@for f in $(FIRMWARE); do rm -f "$(INSTALL_DIR)/$$f"; done; \
	for f in $(INSTALL_DOCS); do rm -f "$(DESTDIR)$(docdir)/$$f"; done; \
	rmdir "$(INSTALL_DIR)" 2>/dev/null || true; rmdir "$(DESTDIR)$(pkgdatadir)" 2>/dev/null || true; \
	rmdir "$(DESTDIR)$(docdir)" 2>/dev/null || true; \
	echo "removed $(TARGET) from $(DESTDIR)$(pkgdatadir)"

# ---------------------------------------------------------------------------
# What this build is configured to produce, without reading four makefiles.
#
# Tool lookups use `type`, not `command -v`: on Solaris `command` is
# /usr/bin/command, a script that does not take -v, so it fails on the host it
# is meant to check.
.PHONY: config help
# `make help`: the usage text at the top of this file
help:
	@awk 'NR >= 3 { if ($$0 == "") exit; print }' $(firstword $(MAKEFILE_LIST)) | sed 's/^# \{0,1\}//'


config:
	@echo "host"
	@printf '  %-14s %s\n' "uname"     "$(UNAME_S) `uname -m`"
	@printf '  %-14s %s\n' "toolchain" "$(TOOLCHAIN)"
	@printf '  %-14s %s\n' "outdir"    "$(OUTDIR)$(if $(filter $(CANONICAL_TREE),$(CURDIR)),, (self-contained: not CANONICAL_TREE))"
	@printf '  %-14s %s\n' "workdir"   "$(WORKDIR)"
	@printf '  %-14s %s\n' "install"   "$(DESTDIR)$(pkgdatadir)/$(TARGET)  (make install)"
	@echo
	@echo "machine description"
	@printf '  %-14s %s\n' "preset"    "$(TARGET)"
	@printf '  %-14s %s\n' "legion-io" "$(MD_LEGION_IO)"
	@printf '  %-14s %s\n' "pci"       "$(MD_PCI)"
	@printf '  %-14s %s\n' "memory"    "$(MD_MEM) MB"
	@printf '  %-14s %s\n' "banner"    "$(BANNER_NAME)"
	@echo
	@echo "hypervisor"
	@printf '  %-14s %s\n' "variant"   "$(HV_PLATFORM)/$(HV_VARIANT)"
	@printf '  %-14s %s\n' "console"   "$(if $(filter yes,$(HV_UART)),hv UART on: needs a QEMU with the niagara-hvuart-console patch,off (stock QEMU))"
	@printf '  %-14s %s\n' "options"   "$(HV_OPTIONS)"
	@echo
	@echo "obp"
	@printf '  %-14s %s\n' "target"    "$(OBP_PLATFORM)/$(OBP_TARGET)"
ifeq ($(TOOLCHAIN),sun)
	@printf '  %-14s %s\n' "source"    "built here, Sun toolchain"
else
	@printf '  %-14s %s\n' "source"    "built here, gnu toolchain + qemu-sparc64/-sparc32plus"
	@printf '  %-14s %s\n' "emulator"  "`command -v $(QEMU_SPARC64) 2>/dev/null || echo '$(QEMU_SPARC64) MISSING'`"
	@printf '  %-14s %s\n' "emulator32" "`command -v $(QEMU_SPARC32) 2>/dev/null || echo '$(QEMU_SPARC32) MISSING'`"
endif
	@echo
	@echo "tools"
ifeq ($(TOOLCHAIN),sun)
	@printf '  %-14s %s\n' "cc"        "$(SUN_STUDIO)/bin/cc"
	@printf '  %-14s %s\n' "make"      "$(MAKE_SUN)"
	@printf '  %-14s %s\n' "path"      "$(SUN_PATH)"
else
	@printf '  %-14s %s\n' "cc"        "`type $(HOST_GCC) 2>/dev/null || echo MISSING`"
	@printf '  %-14s %s\n' "cross"     "`type sparc64-linux-gnu-gcc 2>/dev/null || echo MISSING`"
endif
	@printf '  %-14s %s\n' "flex"      "`PATH=$(SUN_PATH):$$PATH type $(FLEX) 2>/dev/null || echo MISSING`"
	@printf '  %-14s %s\n' "md cpp"    "$(MD_CPP)"
	@echo
	@echo "edit config.mk to change any of this, or override on the command"
	@echo "line: make TARGET=pci MD_MEM=2048"

endif   # TARGET=all fan-out
