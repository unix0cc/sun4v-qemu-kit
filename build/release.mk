# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# make release        firmware release tarball from a clean commit (build/release.sh, where the reasons are)
# make release-check  build it twice at the same fixed path and compare; the second build runs under umask 077 and another locale
#
# Output: $(RELEASE_OUT)/sun4v-qemu-kit-<rev>.tar.gz and .sha256. RELEASE_OUT is a sibling of OUTDIR, so
# `make clean` / `make all` (which wipe OUTDIR) never touch a finished release.

RELEASE_OUT ?= $(patsubst %/,%,$(dir $(patsubst %/,%,$(OUTDIR))))/release

.PHONY: release release-check

release:
	build/release.sh "$(RELEASE_OUT)"

release-check:
	@set -e; t=`mktemp -d`; trap 'rm -rf $$t' EXIT; \
	build/release.sh "$$t/a" >/dev/null; \
	( umask 077; LC_ALL=en_US.UTF-8 build/release.sh "$$t/b" >/dev/null ); \
	if cmp -s "$$t"/a/*.tar.gz "$$t"/b/*.tar.gz; then \
	    echo "release-check: two builds at $${RELEASE_ROOT:-$${TMPDIR:-/tmp}/sun4v-qemu-kit-release-`id -u`} give the same tarball:"; cat "$$t"/a/*.sha256; \
	else echo "release-check: the two tarballs DIFFER" >&2; \
	    for c in a b; do mkdir -p $$t/x$$c; tar -xzf $$t/$$c/*.tar.gz -C $$t/x$$c; done; \
	    diff -rq $$t/xa $$t/xb >&2 || true; exit 1; fi
