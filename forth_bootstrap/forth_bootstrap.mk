# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# make bootstrap-check     derive the committed seed from source with cforth (sparc32, under qemu-user) and compare: forth_bootstrap/README
# make bootstrap-chain     the whole dictionary chain from that derived seed (forth_bootstrap/chain.sh)
# make bootstrap-negative  the negative control: a modified source must make bootstrap-check fail
# All three print SKIP and succeed when sparc64-linux-gnu-gcc or the sparc binfmt_misc handler is missing. Not part of
# `make all`, `make test` or `make release`.

.PHONY: bootstrap-check bootstrap-chain bootstrap-negative

bootstrap-check:
	@forth_bootstrap/check-seed.sh; rc=$$?; [ $$rc = 77 ] && exit 0; exit $$rc

bootstrap-chain:
	@forth_bootstrap/chain.sh; rc=$$?; [ $$rc = 77 ] && exit 0; exit $$rc

bootstrap-negative:
	@forth_bootstrap/tests/negative.sh; rc=$$?; [ $$rc = 77 ] && exit 0; exit $$rc
