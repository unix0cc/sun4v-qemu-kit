#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# pack-md.sh <REPO> <STAGE> -- copy every tracked file of <REPO>/md into <STAGE>/md, keeping the paths (the GPLv2 source bundle of a
# release). One tar run on the whole list: `xargs tar` would cut a long list into several archives, and `tar -xf -` stops at the
# first end-of-archive block, so the files of the later ones would be dropped without a word (tests/full/tools/run).
set -euo pipefail
REPO=${1:?usage: pack-md.sh <REPO> <STAGE>}; STAGE=${2:?usage: pack-md.sh <REPO> <STAGE>}
( cd "$REPO" && git ls-files -z md | tar -cf - --null -T - ) | tar -xf - -C "$STAGE"
