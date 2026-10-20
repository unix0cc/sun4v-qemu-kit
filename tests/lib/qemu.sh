# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# Shared by tests/full/boot/run and tests/smoke/run. Sourced.
#
# resolve_qemu sets Q (the qemu-system-sparc64 to use) and SRC (where it came from):
#   QEMU=<path>   an explicit override, used as is
#   otherwise     qemu-system-sparc64 on PATH, which must belong to the Ubuntu/Debian package qemu-system-sparc
# Nothing is downloaded or unpacked: the package is a requirement (REQUIREMENTS.LINUX, "Packages"). Our own patched
# QEMU builds are deliberately not used by the tests that source this.
resolve_qemu() {
  if [ -n "${QEMU:-}" ]; then Q=$QEMU; SRC="QEMU= override (not vouched for)"; return; fi
  local p; p=$(command -v qemu-system-sparc64 2>/dev/null || true)
  if [ -n "$p" ] && dpkg -S "$p" 2>/dev/null | grep -q '^qemu-system-sparc:'; then
    Q=$p; SRC="dpkg package qemu-system-sparc $(dpkg-query -W -f='${Version}' qemu-system-sparc)"; return
  fi
  echo "cannot run: qemu-system-sparc64 from the distribution package is not installed." >&2
  echo "  install it:  sudo apt install qemu-system-sparc      (see REQUIREMENTS.LINUX, \"Packages\")" >&2
  echo "  or point QEMU= at a qemu-system-sparc64 of your own (then the result is not the tested configuration)." >&2
  exit 2
}
print_qemu() {
  echo "QEMU: $($Q --version | head -1)"; echo "      $Q"; echo "      $SRC; sha256 $(sha256sum < "$Q" | cut -c1-16)"
}
