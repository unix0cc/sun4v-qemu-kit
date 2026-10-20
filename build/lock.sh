#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
# lock.sh <WORKDIR> [check]
#
# Two makes in one OUTDIR would corrupt each other: `all` starts with `clean`. The make that builds in a work directory
# writes its process id to <WORKDIR>.lock (next to the work directory, not inside it: `clean` removes that). A second make
# for the same OUTDIR finds the id of a live make there and stops. A lock of a make that is gone (crashed, killed) is taken
# over; nothing has to remove it. Silent and exit 0 when the lock is ours; otherwise prints why and exits 1 (the Makefile turns
# that into an error at parse time). When the make cannot be found (no ps -o), no lock is made.
# Bourne sh (Solaris 10): no $( ), no ${x#y}, no test -e, no $PPID, no set -C; `ln` makes the write exclusive.
lock=$1.lock
# our make: the nearest parent whose command is a make (make, gmake)
# (Solaris 10's Bourne sh has no $PPID: ask ps for the parent of this shell.)
pid=`ps -o ppid= -p "$$" 2>/dev/null | tr -d ' '`; n=0; c=
[ -n "$pid" ] || exit 0
while [ "$n" -lt 4 ]; do
    c=`ps -o comm= -p "$pid" 2>/dev/null`
    case "$c" in *make*) break ;; esac
    pid=`ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' '`
    [ -n "$pid" ] || exit 0
    n=`expr $n + 1`
done
case "$c" in *make*) ;; *) exit 0 ;; esac

alive_make() {
    kill -0 "$1" 2>/dev/null || return 1
    oc=`ps -o comm= -p "$1" 2>/dev/null`
    case "$oc" in *make*) return 0 ;; esac
    return 1
}
# Taking over a lock whose make is gone: two makes that both saw it stale must not each remove the lock the other has just made.
# So the takeover itself is exclusive (the guard file <lock>.take, made with ln as the lock is), and the owner is read again
# under it: a lock that went live meanwhile is left alone. A guard whose make is gone is removed and tried again.
guard=$lock.take
take_over() {
    echo "$pid" > "$guard.$$" 2>/dev/null
    if ln "$guard.$$" "$guard" 2>/dev/null; then
        rm -f "$guard.$$"
        owner=`cat "$lock" 2>/dev/null`
        if [ -n "$owner" ] && [ "$owner" != "$pid" ] && alive_make "$owner"; then rm -f "$guard"; return 1; fi
        rm -f "$lock"
        echo "$pid" > "$lock.$$" 2>/dev/null
        ln "$lock.$$" "$lock" 2>/dev/null; rc=$?
        rm -f "$lock.$$" "$guard"
        return $rc
    fi
    rm -f "$guard.$$"
    g=`cat "$guard" 2>/dev/null`
    if [ -z "$g" ] || { [ "$g" != "$pid" ] && alive_make "$g"; }; then sleep 1; else rm -f "$guard"; fi
    return 1
}
# `check` (a dry run, make -n): say whether another make holds the lock, but make nothing and take nothing over
if [ "${2:-}" = check ]; then
    owner=`cat "$lock" 2>/dev/null`
    if [ -n "$owner" ] && [ "$owner" != "$pid" ] && alive_make "$owner"; then
        echo "another make (process $owner) is working on this OUTDIR (lock: $lock). Wait for it, or use another OUTDIR; if it is gone, remove $lock"
        exit 1
    fi
    exit 0
fi
# the lock is a file next to WORKDIR: its directory has to be there (WORKDIR itself is made later, by build/workdir.sh)
dir=`dirname "$lock"`
[ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || { echo "cannot make the lock $lock: the directory $dir does not exist and cannot be made"; exit 1; }
try=0
while [ "$try" -lt 5 ]; do
    if [ -f "$lock" ]; then
        owner=`cat "$lock" 2>/dev/null`
        if [ "$owner" = "$pid" ]; then exit 0; fi
        if [ -n "$owner" ] && alive_make "$owner"; then
            echo "another make (process $owner) is working on this OUTDIR (lock: $lock). Wait for it, or use another OUTDIR; if it is gone, remove $lock"
            exit 1
        fi
        if take_over; then exit 0; fi
    else
        # ln fails when the lock exists: an exclusive create (Solaris 10's Bourne sh has no set -C)
        echo "$pid" > "$lock.$$" 2>/dev/null
        if ln "$lock.$$" "$lock" 2>/dev/null; then rm -f "$lock.$$"; exit 0; fi
        rm -f "$lock.$$"
    fi
    try=`expr $try + 1`
done
echo "cannot make the lock $lock"
exit 1
