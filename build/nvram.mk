# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# nvram1 -- the NVRAM image QEMU insists on, filled with zeros.
#
#   make nvram
#
# Zeros are the correct content, not a placeholder. Nothing in this stack reads
# the file:
#
#   - the OBP image built here has no NVRAM driver
#     (arch/sun4v/niagara/release/dropins.src has no nvram entry, unlike
#     niagara2/release which carries legion-nvram);
#   - the hypervisor never references 0x1f11000000;
#   - the MD's nvram node has no `reg`, only cfg-handle = 2.
#
# Measured 2026-08-24: an all-zero image gives console output byte-identical to
# Sun's shipped nvram1, through to the ok prompt.
#
# The requirement is QEMU's. niagara.c does add_rom_or_fail("nvram1",
# NIAGARA_NVRAM_BASE) and exits if the file will not load, so it must exist at
# NIAGARA_NVRAM_SIZE bytes.
#
# OBP's real configuration -- boot-device, console, devaliases -- comes from the
# guest MD (nodes variables / options / devalias). That is what to edit.
#
# build/nvram/mknvram.py can write a structured image with real variable
# records. It is kept because it is the only decoding of that format we have.
# This target does not call it: python3 is not on every Solaris host, dd is.
# build/nvram/README explains what making the file meaningful would cost.

.PHONY: nvram nvram-clean

nvram: $(OUTDIR)/nvram1

$(OUTDIR)/nvram1:
	@mkdir -p $(OUTDIR)
	dd if=/dev/zero of=$@ bs=$(NVRAM_SIZE) count=1 2>/dev/null
	@echo "nvram1 -> $@ ($(NVRAM_SIZE) zero bytes)"

nvram-clean:
	rm -f $(OUTDIR)/nvram1
