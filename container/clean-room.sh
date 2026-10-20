#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# clean-room.sh <image> [commit] [command...]
# A clean room in a container: a fresh clone of THIS repository at <commit> (default: HEAD of the checkout this script is in;
# nothing of the working tree, no build output) mounted as /src in a fresh container of <image> (see container/README).
# With no command: an interactive bash, to build by hand. With a command: run it and exit with its status.
# /log is a directory that outlives the container, for logs. The clone and /log stay under $CR/<image>/ (default
# ${TMPDIR:-/tmp}/sun4v-clean-room/<image>/), the container is removed.
#   container/clean-room.sh sun4v-qemu-kit-build-debian13
#   container/clean-room.sh sun4v-qemu-kit-build-ubuntu2604 HEAD sh -c './configure && make all test-all'
# GUEST_DISK=<file on the host> makes the login gate run: the file is mounted read-only as /images/<name> and GUEST_DISK is set to it.
#   GUEST_DISK=/path/disk.s10hw2 container/clean-room.sh sun4v-qemu-kit-build-debian13 HEAD sh -c './configure && make all test-all'
set -eu
IMG=${1:?usage: clean-room.sh <image> [commit] [command...]}; REV=${2:-HEAD}; [ $# -ge 2 ] && shift 2 || shift
REPO=$(cd "$(dirname "$0")/.." && pwd)
CR=${CR:-${TMPDIR:-/tmp}/sun4v-clean-room}
D=$CR/$IMG
case "$D" in /|""|/tmp|/tmp/) echo "clean-room: refusing $D" >&2; exit 2;; esac
rm -rf "$D"; mkdir -p "$D/log"
git -c init.defaultBranch=main clone -q --no-hardlinks "$REPO" "$D/src"
git -C "$D/src" checkout -q "$(git -C "$REPO" rev-parse "$REV")"
echo "image $IMG, commit $(git -C "$D/src" rev-parse --short=12 HEAD); /src = the clone, /log = $D/log" >&2
T=; [ -t 0 ] && T=-it
G=; if [ -n "${GUEST_DISK:-}" ]; then [ -f "$GUEST_DISK" ] || { echo "clean-room: GUEST_DISK $GUEST_DISK: no such file" >&2; exit 2; }
  G="-v $(readlink -f "$GUEST_DISK"):/images/$(basename "$GUEST_DISK"):ro -e GUEST_DISK=/images/$(basename "$GUEST_DISK")"; fi
if [ $# -eq 0 ]; then set -- bash; fi
exec podman run $T --rm --userns=keep-id -e SOURCE_DATE_EPOCH $G -v "$D/src":/src -v "$D/log":/log -w /src -e HOME=/log "$IMG" "$@"
