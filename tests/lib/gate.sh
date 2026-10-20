#!/bin/bash
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# gate.sh NAME COMMAND [ARGS...] -- run one test gate and close its output with one result line in the format tests/run-all uses:
#
#     ✔ PASS  login   1 checks, 35 s          ✘ FAIL  md   exit 1, 12 checks, 4 s          ○ SKIP  login   GUEST_DISK is not set ...
#
# The gate's own output is streamed as it comes. PASS: exit 0. SKIP: the gate printed `skip ...` and exited 3 (exit 0 here: make
# would turn a 3 into an error). FAIL: any other exit, which is returned unchanged. "Checks" is the number of `ok ...` / `PASS ...` /
# `FAIL ...` lines the gate printed; exit 0 with none of them is a FAIL (a gate that checked nothing has not passed). Colour and glyphs only on a terminal that can show them (NO_COLOR, TERM=dumb turn them off).
# Under tests/run-all (RUN_ALL set) the result line is left to the runner, only the exit-3 mapping stays.
name=$1; shift
if [ -n "${RUN_ALL:-}" ]; then "$@"; rc=$?; [ "$rc" -eq 3 ] && exit 0; exit "$rc"; fi
tmp=$(mktemp "${TMPDIR:-/tmp}/gate.XXXXXX") || exit 2
trap 'rm -f "$tmp"' EXIT
SECONDS=0
set -o pipefail
"$@" 2>&1 | tee "$tmp"
rc=${PIPESTATUS[0]}
dt=$SECONDS
# An ERE grep with POSIX classes that this machine has: Solaris' /usr/bin/grep has no -E and its egrep no [[:space:]]
# (/usr/xpg4/bin/grep -E has both), and GNU grep 3.8+ warns about egrep.
if echo x | grep -E x > /dev/null 2>&1; then ERE="grep -E"
elif [ -x /usr/xpg4/bin/grep ]; then ERE="/usr/xpg4/bin/grep -E"
else ERE=egrep; fi
# Solaris' sed does not know \x1b: put the ESC byte in the script itself.
ESC=$(printf '\033')
nok=$(sed "s/${ESC}\[[0-9;]*[A-Za-z]//g" "$tmp" | $ERE -c '^[[:space:]]*(ok|PASS)([^[:alnum:]_]|$)')
nbad=$(sed "s/${ESC}\[[0-9;]*[A-Za-z]//g" "$tmp" | $ERE -c '^[[:space:]]*(FAIL|FAILED|not ok)([^[:alnum:]_]|$)')
skipline=$(grep '^skip' "$tmp" | head -1 | sed 's/^skip[[:space:]]*//')
if [ "$rc" -eq 3 ] || { [ "$rc" -eq 0 ] && [ "$nok" -eq 0 ] && [ "$nbad" -eq 0 ] && [ -n "$skipline" ]; }; then res=SKIP; note=$skipline; out=0
elif [ "$rc" -eq 0 ] && [ "$nbad" -gt 0 ]; then res=FAIL; note="exit 0, but $nbad FAIL line(s) printed, $dt s"; out=1
elif [ "$rc" -eq 0 ] && [ "$((nok + nbad))" -eq 0 ]; then res=FAIL; note="exit 0, but 0 checks: the gate printed no ok/PASS/FAIL line, $dt s"; out=1
elif [ "$rc" -eq 0 ]; then res=PASS; note="$((nok + nbad)) checks, $dt s"; out=0
else res=FAIL; note="exit $rc, $((nok + nbad)) checks, $dt s"; out=$rc; fi
color=; uni=
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  color=1
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *UTF-8*|*utf-8*|*UTF8*|*utf8*) uni=1;; esac
fi
case $res in
  PASS) mark=+; code='32'; [ -n "$uni" ] && mark=$(printf '\xe2\x9c\x94');;
  FAIL) mark=x; code='31;1'; [ -n "$uni" ] && mark=$(printf '\xe2\x9c\x98');;
  SKIP) mark=-; code='33'; [ -n "$uni" ] && mark=$(printf '\xe2\x97\x8b');;
esac
if [ -n "$color" ]; then printf '\033[%sm%s %s\033[0m %-6s \033[2m%s\033[0m\n' "$code" "$mark" "$res" "$name" "$note"
else printf '%s %s %-6s %s\n' "$mark" "$res" "$name" "$note"; fi
exit "$out"
