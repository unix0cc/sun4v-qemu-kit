# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# engine/Makefile -- builds every tool obp-gnu.mk needs; the substitution
# inventory it implements is TESTS section 6.
#
#   forth64            cross-built, sparc64-linux-gnu, run under qemu-sparc64
#   forth32            the same sources -m32 (the sparc64 cross gcc's multilib,
#                       gcc-13-multilib-sparc64-linux-gnu), run under
#                       qemu-sparc32plus -- Sun's os/unix/sparc/forth, which the
#                       dictionary bootstrap from forth.dic needs (TESTS,
#                       dic-kernels)
#   makedi-sparc        \ cross-built, sparc64-linux-gnu, run under
#   makeprom-sparc      / qemu-sparc64 -- byte-order-safe and
#                         pointer-safe; NOT run natively, see below
#   didepend            native x86_64 -- text-processing only, no on-disk
#                       binary-format writes, portable as-is
#                       (comp.c and the checksum sources are compiled into
#                       the -sparc tools above, not built natively)
#
# makedi/makeprom are deliberately NOT built native-x86_64-only: sys/dropins.h's
# on-disk OBMD header has no explicit byte order anywhere in the source
# (correct only because every host that ever built this before was
# big-endian SPARC), so a native little-endian build silently writes wrong
# header bytes with no error. Running the real sparc64 target code under
# qemu-sparc64 sidesteps that without touching Sun's header.

# GNU_CSTD: set by ./configure for a gcc whose default is C23 (GCC 15 and later), where `f()` means
# `f(void)` and this K&R code no longer compiles. Empty otherwise.
SPARC64_CC   ?= sparc64-linux-gnu-gcc $(GNU_CSTD)
SPARC32_CC   ?= $(SPARC64_CC) -m32
SPARC64_LD   ?= sparc64-linux-gnu-ld
SPARC64_SIZE ?= sparc64-linux-gnu-size
# The host's own gcc (HOST_GCC: ./configure --with-gcc, passed on by build/obp.mk). `CC ?= gcc` would not do: make defines CC itself
# (cc), so the ?= never applied and the host tools were built by whatever `cc` is.
HOST_GCC     ?= gcc
# The host tools are K&R code too: a host gcc whose default is C23 (GCC 15) rejects them (didepend.c:735).
CC           := $(HOST_GCC) -std=gnu17

OBP_SRC      ?= $(abspath ../../../../src/obp/obp)
TOOLS_SRC    ?= $(abspath ../../../../src/obp/tools)
INCLUDE_SRC  ?= $(abspath ../../../../src/obp/include)
LIB_SRC      ?= $(abspath ../../../../src/obp/lib)
# The gnu-path-only source patches (engine + host tools). patches/obp/forth/
# is the other set, applied to the OBP tree itself by obp-gnu.mk.
GNU_PATCHES  ?= $(abspath ../../../../patches/obp/gnu)

OUT ?= out
$(shell mkdir -p $(OUT) $(OUT)/sys)

COMPAT_H := compat.h
# sys/dropins.h and sys/dilib.h are #include <sys/...>: stage a local sys/
# directory so both the native and cross compiles find them without an
# absolute -I into the real checkout.
$(OUT)/sys/dropins.h: $(INCLUDE_SRC)/sys/dropins.h
	cp $< $@
$(OUT)/sys/dilib.h: $(INCLUDE_SRC)/sys/dilib.h
	cp $< $@
STAGE_HDRS := $(OUT)/sys/dropins.h $(OUT)/sys/dilib.h

# ---------------------------------------------------------------- engine --

# What GCC 14 refuses by default, refused here on GCC 13 too, plus -Wformat:
# after patches/obp/gnu/{engine-tools-c99-decls,printf-widths}.patch these
# classes are clean, and the only way they stay clean is if the build fails
# the moment one comes back. With engine-warning-cleanups.patch the engine
# compiles with no warning at the default level.
#
# Not in the list, deliberately: -Wreturn-type. GCC 14's fatal subset of it
# (-Wreturn-mismatch, `return;` in an int function) has no flag of its own
# on GCC 13, and the wider warning (-Wall or -Wreturn-type, and a real
# compile: -fsyntax-only never shows it) fires on ten wrapper.c functions
# that fall off the end: c_key, s_flushcache, pr_error, emacs, m_free,
# f_init, f_op, f_move, f_rows, f_cols. Left as Sun wrote them, by decision
# (2026-09-29). `syscall` (os/unix/sparc/sys.fth) only parks %o0 in
# sysretval, and no caller in src/obp reads it for these; c_key falls off
# only after s_bye(), which exits. Adding the returns was tried and measured
# inert -- every saved image and openboot.bin byte-identical, legion and pci
# -- so it would fix no symptom and only add a patch to explain. No compiler
# rejects falling off the end; revisit only if one starts to.
STRICT = -Werror=implicit-function-declaration -Werror=implicit-int -Werror=format

ENGINE_CFLAGS = -O2 -fcommon -DSYS5 -DUNIX -DSCCS -UDLOPEN \
    '-DDEF_DICT=(512*1024L)' -I. -I$(OUT) -I$(OBP_SRC)/os/unix -I$(LIB_SRC) \
    -include $(COMPAT_H) $(STRICT)

# Sources the gnu path patches are staged under $(OUT) -- os/unix/ from
# $(OBP_SRC), tools/ from $(TOOLS_SRC), the same relative paths the patches
# carry -- and every patch in GNU_PATCH_ORDER is applied there, in that
# order, once. src/obp itself is never touched. A change to any patch or any
# staged source re-stages the lot: the copies are cheap and a half-applied
# stack is not a state worth keeping.
STAGED_ENGINE := $(OUT)/os/unix/wrapper.c $(OUT)/os/unix/fsys.c
STAGED_TOOLS  := $(OUT)/tools/didepend.c $(OUT)/tools/comp.c $(OUT)/tools/makeprom.c \
                 $(OUT)/tools/makedi.c
GNU_PATCH_ORDER := engine-getmem-mprotect-exec.patch makeprom-ptr-roundup.patch \
                   engine-tools-c99-decls.patch printf-widths.patch \
                   engine-warning-cleanups.patch
GNU_PATCH_FILES := $(addprefix $(GNU_PATCHES)/,$(GNU_PATCH_ORDER))

$(OUT)/.patched: $(OBP_SRC)/os/unix/wrapper.c $(OBP_SRC)/os/unix/fsys.c \
                 $(TOOLS_SRC)/didepend.c $(TOOLS_SRC)/comp.c $(TOOLS_SRC)/makeprom.c \
                 $(TOOLS_SRC)/makedi.c $(GNU_PATCH_FILES)
	rm -rf $(OUT)/os $(OUT)/tools
	mkdir -p $(OUT)/os/unix $(OUT)/tools
	cp $(OBP_SRC)/os/unix/wrapper.c $(OBP_SRC)/os/unix/fsys.c $(OUT)/os/unix/
	cp $(TOOLS_SRC)/didepend.c $(TOOLS_SRC)/comp.c $(TOOLS_SRC)/makeprom.c $(TOOLS_SRC)/makedi.c $(OUT)/tools/
	$(foreach p,$(GNU_PATCH_FILES),patch -s -p1 -d $(OUT) < $(p) &&) true
	touch $@
$(STAGED_ENGINE) $(STAGED_TOOLS): $(OUT)/.patched

$(OUT)/wrapper.o: $(OUT)/os/unix/wrapper.c $(STAGE_HDRS)
	$(SPARC64_CC) $(ENGINE_CFLAGS) -c $(OUT)/os/unix/wrapper.c -o $@

$(OUT)/fsys.o: $(OUT)/os/unix/fsys.c $(STAGE_HDRS)
	$(SPARC64_CC) $(ENGINE_CFLAGS) -c $< -o $@

$(OUT)/termcap-stub.o: termcap-stub.c
	$(SPARC64_CC) $(ENGINE_CFLAGS) -c $< -o $@

# forth64 links -lxref -ldef, same as Sun's own os/unix/sparc(v9)/depend.mk --
# these are the same host libraries makedi-sparc/makeprom-sparc need, built
# once for sparc64 here.
LIBXREF_SRC = $(TOOLS_SRC)/libxref
XREF_OBJS = datafile filepath find xref xref_support
XREF_OBJS_SPARC := $(addprefix $(OUT)/xref-,$(addsuffix .o,$(XREF_OBJS)))

$(OUT)/xref-%.o: $(LIBXREF_SRC)/%.c $(STAGE_HDRS)
	$(SPARC64_CC) -static -include $(COMPAT_H) $(STRICT) -I. -I$(OUT) -I$(LIBXREF_SRC) -c $< -o $@

$(OUT)/libxref-sparc.a: $(XREF_OBJS_SPARC)
	ar rcs $@ $^

$(OUT)/forth64: $(OUT)/wrapper.o $(OUT)/fsys.o $(OUT)/termcap-stub.o $(OUT)/libxref-sparc.a $(OUT)/libdef-sparc.a
	$(SPARC64_CC) -static -fcommon -o $@ $(OUT)/wrapper.o $(OUT)/fsys.o $(OUT)/termcap-stub.o \
	    -L$(OUT) -lxref-sparc -ldef-sparc -lm

# 32-bit engine: the same three engine sources and libxref/libdef, -m32,
# objects kept apart under $(OUT)/m32. Sun builds os/unix/sparc/forth with
# exactly the flags of the 64-bit one minus -xarch=v9 (reference trace,
# pids 8929-8969), which is what this mirrors.
M32 := $(OUT)/m32
$(shell mkdir -p $(M32))

$(M32)/wrapper.o: $(OUT)/os/unix/wrapper.c $(STAGE_HDRS)
	$(SPARC32_CC) $(ENGINE_CFLAGS) -c $(OUT)/os/unix/wrapper.c -o $@
$(M32)/fsys.o: $(OUT)/os/unix/fsys.c $(STAGE_HDRS)
	$(SPARC32_CC) $(ENGINE_CFLAGS) -c $< -o $@
$(M32)/termcap-stub.o: termcap-stub.c
	$(SPARC32_CC) $(ENGINE_CFLAGS) -c $< -o $@
$(M32)/xref-%.o: $(LIBXREF_SRC)/%.c $(STAGE_HDRS)
	$(SPARC32_CC) -static -include $(COMPAT_H) $(STRICT) -I. -I$(OUT) -I$(LIBXREF_SRC) -c $< -o $@
$(M32)/libxref-sparc.a: $(addprefix $(M32)/xref-,$(addsuffix .o,$(XREF_OBJS)))
	ar rcs $@ $^
$(M32)/defines-sparc.o: $(TOOLS_SRC)/libdef/defines.c $(STAGE_HDRS)
	$(SPARC32_CC) -static -include $(COMPAT_H) $(STRICT) -I. -I$(OUT) -I$(LIB_SRC) -c $< -o $@
$(M32)/libdef-sparc.a: $(M32)/defines-sparc.o
	ar rcs $@ $^

$(OUT)/forth32: $(M32)/wrapper.o $(M32)/fsys.o $(M32)/termcap-stub.o $(M32)/libxref-sparc.a $(M32)/libdef-sparc.a
	$(SPARC32_CC) -static -fcommon -o $@ $(M32)/wrapper.o $(M32)/fsys.o $(M32)/termcap-stub.o \
	    -L$(M32) -lxref-sparc -ldef-sparc -lm

# ------------------------------------------------------------- host tools --
# didepend/makedi/makeprom: native x86_64 gcc for the
# text-processing tool (didepend), cross+qemu for anything writing the
# on-disk OBMD format (makedi, makeprom) -- see the header note.

CHKSRC = $(TOOLS_SRC)/checksum

$(OUT)/checksum-sparc.o: $(CHKSRC)/checksum.c $(STAGE_HDRS)
	$(SPARC64_CC) -static -include $(COMPAT_H) $(STRICT) -I. -I$(OUT) -c $< -o $@
$(OUT)/crc32-sparc.o: $(CHKSRC)/crc32.c $(STAGE_HDRS)
	$(SPARC64_CC) -static -include $(COMPAT_H) $(STRICT) -I. -I$(OUT) -c $< -o $@
$(OUT)/libchksum-sparc.a: $(OUT)/checksum-sparc.o $(OUT)/crc32-sparc.o
	ar rcs $@ $^

$(OUT)/defines.o: $(TOOLS_SRC)/libdef/defines.c $(STAGE_HDRS)
	$(CC) -include $(COMPAT_H) $(STRICT) -I. -I$(OUT) -I$(LIB_SRC) -c $< -o $@
$(OUT)/libdef.a: $(OUT)/defines.o
	ar rcs $@ $^

$(OUT)/defines-sparc.o: $(TOOLS_SRC)/libdef/defines.c $(STAGE_HDRS)
	$(SPARC64_CC) -static -include $(COMPAT_H) $(STRICT) -I. -I$(OUT) -I$(LIB_SRC) -c $< -o $@
$(OUT)/libdef-sparc.a: $(OUT)/defines-sparc.o
	ar rcs $@ $^

$(OUT)/didepend: $(OUT)/tools/didepend.c $(OUT)/libdef.a $(STAGE_HDRS)
	$(CC) -include $(COMPAT_H) $(STRICT) -I. -I$(OUT) -I$(LIB_SRC) -o $@ $< $(OUT)/libdef.a

$(OUT)/makedi-sparc: $(OUT)/tools/makedi.c $(OUT)/tools/comp.c $(OUT)/libchksum-sparc.a $(STAGE_HDRS)
	$(SPARC64_CC) -static -include $(COMPAT_H) $(STRICT) -I. -I$(OUT) -DNOMAIN \
	    -o $@ $(OUT)/tools/makedi.c $(OUT)/tools/comp.c $(OUT)/libchksum-sparc.a

$(OUT)/makeprom-sparc: $(OUT)/tools/makeprom.c $(OUT)/libchksum-sparc.a $(STAGE_HDRS)
	$(SPARC64_CC) -static -include $(COMPAT_H) $(STRICT) -I. -I$(OUT) \
	    -o $@ $(OUT)/tools/makeprom.c $(OUT)/libchksum-sparc.a

.PHONY: all clean
all: $(OUT)/forth64 $(OUT)/forth32 $(OUT)/didepend $(OUT)/makedi-sparc $(OUT)/makeprom-sparc

clean:
	rm -rf $(OUT)
