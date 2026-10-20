# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Exception: the tokenize rule (%.fc, below) is derived from Sun's src/obp/obp/arch/common.mk. Copyright (c) 2006 Sun Microsystems, Inc.
# All Rights Reserved. That rule is under Sun's BSD+ licence (BSD+_License_OpenSPARCT2.txt in this repository; LICENSE_CODE).
# obp-gnu-inner.mk -- the dropins-driven part of the build, run via a
# sub-make invoked with `-C $(OBP_BLD)` from obp-gnu.mk.
#
# Why a separate file, not just `-include dropins.mk` from the top-level
# makefile directly: didepend's generated dropins.mk (and every per-dropin
# depend.mk it `include`s) is written entirely in bare, cwd-relative
# filenames (`vnexus.di: ... vnexus.fc`, `include ${BP}/dev/.../depend.mk`)
# because Sun's own build always `cd $(OBP_BLD) && gmake` first. Rather than
# rewrite those paths (fragile -- tried first, abandoned), this file is run
# with make's own CWD actually set to $(OBP_BLD) via -C, so every relative
# name in Sun's generated files resolves exactly as it does in the real
# build. BP and MAKEDI are passed in as make variable overrides from the
# parent make invocation; ${BP} appears literally, unresolved, in
# dropins.mk's `include` lines and is substituted here like any other make
# variable once this file -includes it.

BP      ?= $(error BP not passed from obp-gnu.mk)
MAKEDI  ?= $(error MAKEDI not passed from obp-gnu.mk)
TOKENIZE ?= $(error TOKENIZE not passed from obp-gnu.mk)



# arch/common.mk's real recipe (FORTHDI is empty here -- it is only
# "headers.di" when a HEADERS file is present, which this build never
# creates): cat every dropin listed in dropins.mk's own builtin.di: line,
# in the order didepend -t printed it.
builtin.di:
	cat $^ > $@

# The generic tokenize rule, from Sun's arch/common.mk %.fc: rule (TOKENRULE),
# with FORTH/TOKENIZEDIC as Sun's (the 32-bit engine on the bootstrapped
# tokenize.dic; only the engine path differs). Sun passes
# `-s "${FTHFLAGS}"` ahead of the tokenize string (common.mk:289); FTHFLAGS is
# empty globally and set per target by dropins.src `buildoptions` lines
# (rewritten into target-specific variables when dropins.mk is generated --
# see obp-gnu.mk). Omitted until 2026-09-20, which dropped vpci.fc's
# `[define] 64BIT-ASSIGNED?`. `-x $*.idx` (xref index) is not reproduced: it
# is a side file, not an input to anything built here.
FTHFLAGS ?=
%.fc:
	@fname=""; for i in $^; do case "$$i" in *.tok) fname="$$i";; esac; done; \
	if [ -n "$$fname" ]; then \
	    $(TOKENIZE) -s "$(FTHFLAGS)" \
	        -s "aout-header? off silent on tokenize $$fname $*.fc"; \
	fi

# Sun's own generated dropins.mk, included unchanged (cwd = $(OBP_BLD)).
include dropins.mk

# bootprom.di, font.di and sun-logo.di deliberately have NO recipes here:
# dropins.mk (bootprom), pkg/termemu/fonts.mk (font) and pkg/sunlogo/logo.mk
# (sun-logo), all pulled in by the include above, carry Sun's own -- and
# they run as-is given MAKEDI/FORTHTOOL/TOOLS from the parent make. An
# override for font.di used to live here and named the dropin
# `gallant-romfont`; fonts.mk names it `fonts`, which was the whole of the
# 17-byte font.di residual against the reference (name field + header
# checksum; the compressed payload was already identical). 2026-09-20.
