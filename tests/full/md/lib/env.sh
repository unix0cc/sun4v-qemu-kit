# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Shared by internal/*.sh. Sourced, not run.
#   REPO    the sun4v-qemu-kit checkout
#   OUT     scratch directory (OUTDIR, default: one mktemp dir per run)
#   MDGEN, MDLINT   the compiler and linter the real build uses (built by `make md`, never a prebuilt one)
#   T1      the pristine OpenSPARC T1 tree: Sun's config sources and Sun's shipped MD binaries
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
UNFOLD=${UNFOLD:-"$HERE/lib/mdunfold.py"}
T1=${T1:-}
OUT=${OUTDIR:-$(mktemp -d "${TMPDIR:-/tmp}/md-test.XXXXXX")}
mkdir -p "$OUT"
CPP=${CPP:-cpp -traditional-cpp}

need() { [ -e "$1" ] || { echo "cannot run: $1 missing ($2)" >&2; exit 2; }; }

# Build every md/<target>/ config once into $OUT/<target>; sets CONFIGS and MDGEN.
build_ours() {
    CONFIGS=$(cd "$REPO/md" && for d in */; do [ -f "$d/1up.pdesc" ] && echo "${d%/}"; done)
    for c in $CONFIGS; do
        [ -f "$OUT/$c/1up-md.bin" ] || make -s -C "$REPO" md TARGET="$c" OUTDIR="$OUT/$c" WORKDIR="$OUT/work-$c" >/dev/null
    done
    MDGEN=$OUT/work-$(echo $CONFIGS | cut -d' ' -f1)/mdtools/mdgen
    MDLINT=${MDGEN%mdgen}mdlint
    need "$MDGEN" "make md builds it"; need "$MDLINT" "make md builds it"
}
