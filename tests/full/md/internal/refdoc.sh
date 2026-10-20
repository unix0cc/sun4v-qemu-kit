#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# md/REFERENCE against our built MDs (lib/refdoc.py): part 1, the nodes, properties and values of the hypervisor MD; parts 2
# and 3, the positions of the guest MD and the counts they state. A failure means the document or an hdesc is out of date.
. "$(dirname "$0")/../lib/env.sh"
build_ours
first=$(echo $CONFIGS | tr ' ' '\n' | grep -x legion || echo "${CONFIGS%% *}")
blobs=("$OUT/$first/1up-hv.bin")
for c in $CONFIGS; do [ "$c" = "$first" ] || blobs+=("$OUT/$c/1up-hv.bin"); done
mds=("$OUT/$first/1up-md.bin")
for c in $CONFIGS; do [ "$c" = "$first" ] || mds+=("$OUT/$c/1up-md.bin"); done
python3 "$HERE/lib/refdoc.py" "$REPO/md/REFERENCE" --hv "${blobs[@]}" --md "${mds[@]}"
