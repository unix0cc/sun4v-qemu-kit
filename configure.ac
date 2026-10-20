dnl SPDX-License-Identifier: BSD-2-Clause
dnl Copyright (c) 2026 sun4v-qemu-kit author(s), see the AUTHORS file
dnl configure.ac -- OPTIONAL front end to config.mk. `make` works without it.
dnl
dnl   autoconf              (on a host that has it; the generated ./configure is kept in the tree so
dnl                          that a Solaris 10 host, which has no autoconf, never needs to run this)
dnl   ./configure [--with-toolchain=gnu|sun] [--with-gcc-cross=DIR] [--with-gcc=DIR] [--with-sun-studio=DIR] ...
dnl   make
dnl
dnl What it does: finds the compilers and tools, runs the probes that config.mk and the build
dnl scripts would otherwise meet halfway through a build (does this cross gcc link -m32? does this
dnl cc write stabs? does it turn loops into _memcpy calls? does the system as take -xarch=v9d?),
dnl and writes the answers to config.auto.mk, which config.mk includes first. What configure
dnl leaves out keeps config.mk's default; make's command line still wins over both.
dnl
dnl Written for Solaris 10's Bourne /bin/sh as much as for bash: no $( ), no ${x%%y}, no
dnl `command -v`, no grep -q. The generated configure re-executes under a better shell if it finds one.
dnl m4 eats square brackets: in the C text of a probe write *(p + i), not p[i].
AC_PREREQ([2.69])
AC_INIT([sun4v-qemu-kit], [0], [], [sun4v-qemu-kit])
AC_CONFIG_SRCDIR([build/hv_reset.mk])
AC_CONFIG_FILES([config.auto.mk])

dnl Run from another directory (nfw_oot=yes): a Makefile there that passes every goal on to the Makefile in the
dnl source tree, with this directory's config.auto.mk. Everything stays relative to the source tree, as it is when
dnl configure is run in it. (printf with \t, not a here-document, so that the tabs cannot be lost in an editor;
dnl nfw_d holds the dollar sign because m4 would take a $@ in this text for its own.)
AC_CONFIG_COMMANDS([oot-makefile],
[if test "$nfw_oot" = yes; then
  nfw_d='$'
  nfw_bt='`'
  {
  printf '%s\n' "# Written by configure. The sources are in $nfw_top; every goal is passed on" \
    "# to the Makefile there. The build, config.auto.mk and OUTDIR stay in this directory." \
    "srcdir = $nfw_top" \
    "GUARD:sh = echo 'This Makefile needs GNU make: run ${nfw_bt}gmake${nfw_bt}, not ${nfw_bt}make${nfw_bt}.' >&2; exit 1" \
    '.DEFAULT_GOAL := all' \
    '.PHONY: all distclean'
  for nfw_g in 'all:' '.DEFAULT:'; do
    printf '%s\n' "$nfw_g"
    printf '\t%s\n' "@cd ${nfw_d}(srcdir) && ${nfw_d}(MAKE) CONFIG_AUTO=${nfw_d}(CURDIR)/config.auto.mk ${nfw_d}@"
  done
  printf '%s\n' 'distclean:'
  printf '\t%s\n' '-@cd $(srcdir) && $(MAKE) CONFIG_AUTO=$(CURDIR)/config.auto.mk clean' \
    'rm -f Makefile config.auto.mk config.status config.log' 'rm -rf config.wrap' '@rmdir output 2>/dev/null || true'
  } > Makefile
fi],
[nfw_oot='$nfw_oot'; nfw_top='$nfw_top'])

AC_ARG_WITH([toolchain],
  [AS_HELP_STRING([--with-toolchain=gnu|sun],
     [how reset.bin/q.bin and openboot.bin are built (default: sun on SunOS, gnu elsewhere)])],
  [], [with_toolchain=auto])
AC_ARG_WITH([gcc-cross],
  [AS_HELP_STRING([--with-gcc-cross=DIR],
     [gnu: the sparc64-linux-gnu-* tools are in DIR/bin, or in DIR itself (default: PATH; a DIR that has none is an error, not a fall back to PATH)])],
  [], [with_gcc_cross=])
AC_ARG_WITH([binutils-cross],
  [AS_HELP_STRING([--with-binutils-cross=DIR],
     [gnu: the sparc64-linux-gnu-{as,ld,size,readelf,objcopy,objdump} are in DIR/bin, or in DIR itself, and the cross gcc is made to use them too (default: the ones the gcc has)])],
  [], [with_binutils_cross=])
dnl the old name: an unknown --with option is only a warning to Autoconf, and the build would go on with the wrong gcc
AC_ARG_WITH([gnu-cross], [], [AC_MSG_ERROR([--with-gnu-cross is now --with-gcc-cross])])
AC_ARG_WITH([gcc],
  [AS_HELP_STRING([--with-gcc=DIR],
     [gnu: the host's own gcc, which builds mdgen and mdlint, is DIR/bin/gcc or DIR/gcc (default: gcc on PATH)])],
  [], [with_gcc=])
AC_ARG_WITH([sun-studio],
  [AS_HELP_STRING([--with-sun-studio=DIR],
     [sun: the Sun Studio / Developer Studio installation, DIR, DIR/bin or DIR/SUNWspro has cc (default: the Sun cc on PATH, else the first of /opt/SUNWspro, /opt/developerstudio12.6, ... that has one)])],
  [], [with_sun_studio=])
AC_ARG_WITH([outdir],
  [AS_HELP_STRING([--with-outdir=DIR],
     [where the build writes the firmware set (OUTDIR; default: config.mk's own rule)])],
  [], [with_outdir=])
AC_ARG_WITH([workdir],
  [AS_HELP_STRING([--with-workdir=DIR],
     [where the build keeps what is not the result (WORKDIR; default: $TMPDIR or /var/tmp, in a directory named after OUTDIR). make clean and a second configure remove it])],
  [], [with_workdir=])
dnl the old name: an unknown --with option is only a warning to Autoconf, and the build would go on with the wrong target
AC_ARG_WITH([md-config], [], [AC_MSG_ERROR([--with-md-config is now --with-target])])

AC_ARG_ENABLE([hv-uart],
  [AS_HELP_STRING([--enable-hv-uart],
     [keep the hypervisor's own debug console (CONFIG_HVUART). The firmware then needs a QEMU with the niagara-hvuart-console patch and hangs without it; default: off])],
  [], [enable_hv_uart=no])

AC_ARG_WITH([target],
  [AS_HELP_STRING([--with-target=NAME],
     [TARGET: the machine a plain make builds: any md/NAME/ that has a 1up.pdesc, or all (default: config.mk's own, legion)])],
  [], [with_target=])
AC_ARG_WITH([md-mem],
  [AS_HELP_STRING([--with-md-mem=MB],
     [guest RAM in MB written into the MD (MD_MEM; default: the machine's own, legion 2048, pci 4096). QEMU's -m must be the same number; nothing checks that])],
  [], [with_md_mem=])

dnl configure may be run from another directory (../configure). nfw_top is the source tree, nfw_builddir the
dnl directory configure was run in; the probes call the scripts under build/ by the nfw_top path. In another
dnl directory config.auto.mk and a Makefile that passes every goal on to the source tree are written there, and
dnl the source tree is not touched (the build already writes to OUTDIR). See nfw_oot below.
nfw_top=`cd "$srcdir" && pwd`
nfw_builddir=`pwd`
if test "$nfw_top" = "$nfw_builddir"; then nfw_oot=no; else nfw_oot=yes; fi

dnl A second configure replaces the settings of the first, and with them the work directory the first one's
dnl build used: remove it now (build/workdir.sh removes only a directory that carries its marker).
if test -f config.auto.mk; then
  nfw_old_out=`sed -n 's/^OUTDIR = //p' config.auto.mk | sed 1q`
  nfw_old_wd=`sed -n 's/^WORKDIR = //p' config.auto.mk | sed 1q`
  test -n "$nfw_old_out" || nfw_old_out=$nfw_top/output
  nfw_old_wd=`cd "$nfw_top" && sh build/workdir.sh path "$nfw_old_out" "$nfw_old_wd"`
  ( cd "$nfw_top" && sh build/workdir.sh clean "$nfw_old_wd" "$nfw_top" )
fi

dnl Nothing is taken from a cache, whatever -C or --cache-file says: the probes answer for ONE compiler, and
dnl the cache key does not say which (a -std=gnu17 learned from gcc 16 would outlive a switch to gcc 13).
for nfw_v in `set | grep '^ac_cv_' | sed 's/=.*//'` `set | grep '^nfw_cv_' | sed 's/=.*//'`; do
  unset $nfw_v
done

dnl --- helpers (shell functions: Solaris' /bin/sh has them) ------------------------------
nfw_missing=
nfw_probe_dir=conftest.d

dnl nfw_failed MESSAGE: a configure that stops must not leave the config.auto.mk of an earlier run
dnl behind -- make would go on with settings nobody has checked. Replace it with a file that stops make
dnl and says why. (tr, not sed brackets: m4 eats those.)
nfw_failed() {
  nfw_m=`printf '%s' "$1" | tr '\n$#' '   '`
  printf '%s\n' "\$(error ./configure failed: $nfw_m -- fix that and run ./configure again, or remove config.auto.mk)" > config.auto.mk
}
AC_DEFUN([NFW_FAIL], [nfw_failed "$1"; AC_MSG_ERROR([$1])])

dnl nfw_find NAME: print the first executable NAME on PATH (type prints different things in different shells)
nfw_find() {
  nfw_ifs=$IFS; IFS=:
  for nfw_d in $PATH; do
    test -n "$nfw_d" || nfw_d=.
    if test -f "$nfw_d/$1" && test -x "$nfw_d/$1"; then IFS=$nfw_ifs; printf '%s\n' "$nfw_d/$1"; return 0; fi
  done
  IFS=$nfw_ifs
  return 1
}

dnl nfw_need NAME...: every NAME must be found on PATH; the ones that are not are listed together
nfw_need() {
  for nfw_t in "$@"; do
    AC_MSG_CHECKING([for $nfw_t])
    if nfw_p=`nfw_find $nfw_t` && test -n "$nfw_p"; then
      AC_MSG_RESULT([$nfw_p])
    else
      AC_MSG_RESULT([no])
      nfw_missing="$nfw_missing $nfw_t"
    fi
  done
}

dnl nfw_gnu_patch PATCH: is it GNU patch? Solaris' /usr/bin/patch cannot read a unified diff and then
dnl asks "File to patch:" forever on a build with no terminal. GNU patch answers --version (2.5.9 says
dnl "patch 2.5.9", without "GNU"); Solaris' exits with an error. The same test as check-sun-toolchain.
nfw_gnu_patch() {
  "$1" --version >/dev/null 2>&1 </dev/null
}

dnl nfw_try 'C TEXT' CMD...: write the text to conftest.c in a fresh conftest.d and run CMD there; the
dnl output goes to config.log
nfw_try() {
  rm -rf $nfw_probe_dir; mkdir $nfw_probe_dir || return 1
  printf '%s\n' "$1" > $nfw_probe_dir/conftest.c
  shift
  ( cd $nfw_probe_dir && "$@" ) >&AS_MESSAGE_LOG_FD 2>&1
}

dnl nfw_try_cd CMD...: run CMD in a fresh conftest.d (the caller names its own files); output to config.log
nfw_try_cd() {
  rm -rf $nfw_probe_dir; mkdir $nfw_probe_dir || return 1
  ( cd $nfw_probe_dir && "$@" ) >&AS_MESSAGE_LOG_FD 2>&1
}

dnl The compiler is probed on the hypervisor's OWN sources, not on a stand-in line of C: four files of
dnl src/hypervisor that need nothing generated (the rest wait for offsets.h), compiled with the include
dnl path and the flags the build gives them. A question about what the build will do is answered by doing it.
nfw_hv_src=$nfw_top/src/hypervisor/src
nfw_hv_inc="-I$nfw_hv_src/greatlakes/ontario/include -I$nfw_hv_src/greatlakes/common/include -I$nfw_hv_src/common/include -I$nfw_hv_src/include -I$nfw_top/build/hv_reset/gnu/abi"
nfw_hv_probe_srcs="common/src/support.c common/src/mdsup.c common/src/res_mau.c greatlakes/common/src/svc_init.c"

dnl nfw_hv_gnu EXTRA-FLAGS: (inside conftest.d) compile those sources with the cross gcc
nfw_hv_gnu() {
  for nfw_s in $nfw_hv_probe_srcs; do
    "$nfw_cross_cc" -c -m64 $1 -mcpu=v9 -fPIC -O2 -ffreestanding -D__sparcv9 $nfw_hv_inc \
        -o conftest.o "$nfw_hv_src/$nfw_s" || return 1
  done
}

dnl nfw_md_gnu EXTRA-FLAGS: (inside conftest.d) build mdgen and mdlint the way build/mdtools.mk does, with the
dnl host gcc. The patches are applied to a copy, in conftest.d; src/ is not touched.
nfw_md_gnu() {
  CC="$HOST_GCC $1" FLEX=flex sh "$nfw_top/build/mdtools/gnu/build.sh" "$nfw_hv_src" "`pwd`" \
      "$nfw_top/patches/mdtools/gnu/mdgen-mdlint-host-endian.patch"
}

dnl nfw_dwarf_probe "CC FLAGS" GFLAG "DUMPER" FORMAT: the pipeline that makes offsets.h without `stabs`
dnl (build/hv_reset/offsets-dwarf.sh, README.dwarf) on a struct whose layout is known: does this cc's DWARF,
dnl as this dumper prints it, come out of dwarf2genassym.pl with the right member offset (8, after an int
dnl and padding)? Existence of the dumper says nothing about its output format.
nfw_dwarf_probe() {
  rm -rf $nfw_probe_dir; mkdir $nfw_probe_dir || return 1
  printf 'struct nfwp { int a; long b; };\n' > $nfw_probe_dir/conftest.h
  printf '#include "conftest.h"\n\nnfwp\tNFWP_SIZE\n\tb\tNFWP_B\n' > $nfw_probe_dir/offsets.in
  ( cd $nfw_probe_dir && sh "$nfw_top/build/hv_reset/offsets-dwarf.sh" -t offsets.h -i offsets.in \
      -c "$1 -I." -g "$2" -d "$3" -f "$4" ) >&AS_MESSAGE_LOG_FD 2>&1 || return 1
  grep 'NFWP_B.*0x8' $nfw_probe_dir/offsets.h >/dev/null 2>&1
}

dnl --- the host ---------------------------------------------------------------------------
nfw_uname_s=`uname -s`
nfw_uname_m=`uname -m`
AC_MSG_CHECKING([the toolchain to build with])
case "$with_toolchain" in
auto) if test "$nfw_uname_s" = SunOS; then TOOLCHAIN=sun; else TOOLCHAIN=gnu; fi ;;
gnu|sun) TOOLCHAIN=$with_toolchain ;;
*) AC_MSG_RESULT([$with_toolchain])
   NFW_FAIL([--with-toolchain must be gnu or sun]) ;;
esac
AC_MSG_RESULT([$TOOLCHAIN (host: $nfw_uname_s $nfw_uname_m)])
if test "$TOOLCHAIN" = sun && test "$nfw_uname_s" != SunOS; then
  NFW_FAIL([the sun toolchain builds on Solaris only; this host is $nfw_uname_s])
fi

dnl =========================================================================================
dnl  gnu
dnl =========================================================================================
GNU_CROSS_BIN=
GNU_CSTD=
HOST_GCC=
HOST_CSTD=
nfw_host_version=
QEMU_SPARC64=
QEMU_SPARC32=
nfw_cross_cc=
nfw_cross_version=

dnl The hypervisor is compiled -m64, the OBP engine -m64 and -m32. A link, not only a compile: a gcc
dnl whose -m32 library directory does not resolve compiles fine and fails at -lm.
AC_DEFUN([NFW_CROSS_LINK],
  [AC_CACHE_CHECK([whether the cross gcc compiles and links -$1], [nfw_cv_cross_$1], [
     if nfw_try 'int main(void) { return 0; }' "$nfw_cross_cc" -$1 -o conftest conftest.c -lm; then
       nfw_cv_cross_$1=yes
     else
       nfw_cv_cross_$1=no
     fi])
   test "$nfw_cv_cross_$1" = yes || nfw_missing="$nfw_missing cross-gcc(-$1)"])

if test "$TOOLCHAIN" = gnu; then
  nfw_path=$PATH
  if test -n "$with_gcc_cross"; then
    if test -x "$with_gcc_cross/bin/sparc64-linux-gnu-gcc"; then
      nfw_path=$with_gcc_cross/bin
    else
      nfw_path=$with_gcc_cross
    fi
  fi
  AC_PATH_PROG([nfw_cross_cc], [sparc64-linux-gnu-gcc], [], [$nfw_path])
  if test -z "$nfw_cross_cc"; then
    NFW_FAIL([no sparc64-linux-gnu-gcc (looked in $nfw_path); apt install gcc-sparc64-linux-gnu, or --with-gcc-cross=DIR])
  fi
  GNU_CROSS_BIN=`dirname "$nfw_cross_cc"`
  nfw_bu_tools="as ld size readelf objcopy objdump"
  dnl --with-binutils-cross: a PATH entry alone does not do it. gcc runs its own as and ld by its own search path
  dnl (gcc -print-prog-name=as), so the build would assemble the .s files with the new as and the .c files with
  dnl the old one. And the host gcc that builds mdgen must not see them at all (COMPILER_PATH reached it and
  dnl it called the sparc64 as on x86 code). So: a directory of its own, config.wrap, with the tools as links
  dnl and a sparc64-linux-gnu-gcc that is the real one given -B for them; only the cross gcc goes through it.
  if test -n "$with_binutils_cross"; then
    nfw_bu=
    for nfw_d in "$with_binutils_cross/bin" "$with_binutils_cross"; do
      if test -x "$nfw_d/sparc64-linux-gnu-as"; then nfw_bu=`cd "$nfw_d" && pwd`; break; fi
    done
    if test -z "$nfw_bu"; then
      NFW_FAIL([--with-binutils-cross=$with_binutils_cross: no sparc64-linux-gnu-as in DIR/bin or in DIR])
    fi
    for nfw_t in $nfw_bu_tools; do
      if test ! -x "$nfw_bu/sparc64-linux-gnu-$nfw_t"; then
        NFW_FAIL([--with-binutils-cross: $nfw_bu has no sparc64-linux-gnu-$nfw_t])
      fi
    done
    nfw_wrap=$nfw_builddir/config.wrap
    rm -rf "$nfw_wrap"; mkdir "$nfw_wrap"
    for nfw_t in $nfw_bu_tools; do ln -s "$nfw_bu/sparc64-linux-gnu-$nfw_t" "$nfw_wrap/sparc64-linux-gnu-$nfw_t"; done
    printf '#!/bin/sh\nexec "%s" -B"%s/sparc64-linux-gnu-" "$@"\n' "$nfw_cross_cc" "$nfw_bu" > "$nfw_wrap/sparc64-linux-gnu-gcc"
    chmod +x "$nfw_wrap/sparc64-linux-gnu-gcc"
    nfw_cross_cc=$nfw_wrap/sparc64-linux-gnu-gcc
    GNU_CROSS_BIN=$nfw_wrap
  fi
  PATH=$GNU_CROSS_BIN:$PATH
  nfw_cross_version=`"$nfw_cross_cc" --version 2>/dev/null | sed 1q`
  AC_MSG_NOTICE([cross compiler: $nfw_cross_version])

  nfw_need sparc64-linux-gnu-as sparc64-linux-gnu-ld sparc64-linux-gnu-size \
           sparc64-linux-gnu-objcopy sparc64-linux-gnu-readelf sparc64-linux-gnu-objdump \
           ar cpp awk cmp od sha256sum python3 perl flex patch
  AC_MSG_CHECKING([whether patch is GNU patch])
  if nfw_gnu_patch patch; then
    AC_MSG_RESULT([yes])
  else
    AC_MSG_RESULT([no])
    nfw_missing="$nfw_missing gnu-patch"
  fi

  dnl The as and ld the cross gcc runs and the ones the build calls by name must be the same program. Asked of
  dnl both: the version line each prints. (The build assembles hv's .s with the PATH one, compiles the .c through
  dnl the gcc, which runs its own; a mix does build, and its output cannot be credited to either.)
  AC_CACHE_CHECK([whether the cross gcc runs the same as and ld that the build calls], [nfw_cv_gnu_chain], [
    nfw_cv_gnu_chain=yes
    for nfw_t in as ld; do
      nfw_gt=`"$nfw_cross_cc" -print-prog-name=$nfw_t 2>/dev/null`
      nfw_gv=`"$nfw_gt" --version 2>/dev/null | sed 1q`
      nfw_bv=`sparc64-linux-gnu-$nfw_t --version 2>/dev/null | sed 1q`
      if test -z "$nfw_gv" || test "$nfw_gv" != "$nfw_bv"; then
        if test "$nfw_cv_gnu_chain" = yes; then nfw_cv_gnu_chain="no:"; fi
        nfw_cv_gnu_chain="$nfw_cv_gnu_chain $nfw_t: gcc runs $nfw_gt ($nfw_gv), the build calls ($nfw_bv);"
      fi
    done])
  case "$nfw_cv_gnu_chain" in
  yes) ;;
  *) nfw_missing="$nfw_missing as/ld(the cross gcc and the build use different ones: $nfw_cv_gnu_chain; --with-binutils-cross=DIR makes them the same)" ;;
  esac

  NFW_CROSS_LINK([m64])
  NFW_CROSS_LINK([m32])

  dnl GCC 15 and later default to C23, which the hypervisor's sources predate (`false` is a keyword there,
  dnl `f()` means `f(void)`). Whether this gcc needs -std=gnu17 is decided by compiling the sources.
  AC_CACHE_CHECK([whether the cross gcc needs -std=gnu17 for the hypervisor sources], [nfw_cv_cross_cstd], [
    if nfw_try_cd nfw_hv_gnu ''; then
      nfw_cv_cross_cstd=no
    elif nfw_try_cd nfw_hv_gnu -std=gnu17; then
      nfw_cv_cross_cstd=-std=gnu17
    else
      nfw_cv_cross_cstd=failed
    fi])
  case "$nfw_cv_cross_cstd" in
  no) ;;
  failed) nfw_missing="$nfw_missing cross-gcc(cannot compile the hypervisor sources, with or without -std=gnu17: config.log)" ;;
  *) GNU_CSTD=$nfw_cv_cross_cstd ;;
  esac

  dnl The host's own gcc builds mdgen and mdlint (build/mdtools/gnu/build.sh), a different compiler from the
  dnl cross one. It is not put on PATH: the build names it, as HOST_GCC. Whether it needs -std=gnu17 is decided
  dnl by building mdgen and mdlint with it.
  nfw_hpath=$PATH
  if test -n "$with_gcc"; then
    if test -x "$with_gcc/bin/gcc"; then
      nfw_hpath=$with_gcc/bin
    else
      nfw_hpath=$with_gcc
    fi
  fi
  AC_PATH_PROG([HOST_GCC], [gcc], [], [$nfw_hpath])
  if test -z "$HOST_GCC"; then
    NFW_FAIL([no gcc (looked in $nfw_hpath); apt install gcc, or --with-gcc=DIR])
  fi
  nfw_host_version=`"$HOST_GCC" --version 2>/dev/null | sed 1q`
  AC_MSG_NOTICE([host compiler: $nfw_host_version])
  AC_CACHE_CHECK([whether the host gcc needs -std=gnu17 for mdgen and mdlint], [nfw_cv_host_cstd], [
    if nfw_try_cd nfw_md_gnu ''; then
      nfw_cv_host_cstd=no
    elif nfw_try_cd nfw_md_gnu -std=gnu17; then
      nfw_cv_host_cstd=-std=gnu17
    else
      nfw_cv_host_cstd=failed
    fi])
  case "$nfw_cv_host_cstd" in
  no) ;;
  failed) nfw_missing="$nfw_missing host-gcc(cannot build mdgen and mdlint, with or without -std=gnu17: config.log)" ;;
  *) HOST_CSTD=$nfw_cv_host_cstd ;;
  esac

  dnl The assembler and linker the hypervisor build calls: -Av9d for the hyperprivileged registers
  dnl (rdhpr), and ld --no-warn-execstack (binutils 2.39 and later; the build passes it to every link).
  AC_CACHE_CHECK([whether sparc64-linux-gnu-as accepts -Av9d and ld --no-warn-execstack], [nfw_cv_gnu_as_ld], [
    rm -rf $nfw_probe_dir; mkdir $nfw_probe_dir
    printf '\trdhpr\t%%hpstate, %%g1\n' > $nfw_probe_dir/conftest.s
    if ( cd $nfw_probe_dir && sparc64-linux-gnu-as -Av9d -o conftest.o conftest.s \
         && sparc64-linux-gnu-ld --no-warn-execstack -e 0 -o conftest conftest.o ) >&AS_MESSAGE_LOG_FD 2>&1; then
      nfw_cv_gnu_as_ld=yes
    else
      nfw_cv_gnu_as_ld=no
    fi])
  test "$nfw_cv_gnu_as_ld" = yes || nfw_missing="$nfw_missing as/ld(-Av9d,--no-warn-execstack)"

  dnl The DWARF path for offsets.h: gcc writes it, readelf prints it, dwarf2genassym.pl reads it.
  AC_CACHE_CHECK([whether offsets.h can be made from this gcc's DWARF], [nfw_cv_gnu_dwarf], [
    if nfw_dwarf_probe "$nfw_cross_cc -m64 $GNU_CSTD" -gdwarf-4 "sparc64-linux-gnu-readelf --debug-dump=info" readelf; then
      nfw_cv_gnu_dwarf=yes
    else
      nfw_cv_gnu_dwarf=no
    fi])
  test "$nfw_cv_gnu_dwarf" = yes || nfw_missing="$nfw_missing dwarf(offsets.h)"

  dnl The linux-user emulators the OBP engine runs under. Found by name, then RUN: a static program built
  dnl the way the engines are (-static, -m64 / -m32) must print 42 under each. An emulator that exists but
  dnl cannot run that would fail in the middle of the OBP build.
  AC_PATH_PROGS([QEMU_SPARC64], [qemu-sparc64-static qemu-sparc64], [], [$PATH:$HOME/build/qemu-linux-user])
  AC_PATH_PROGS([QEMU_SPARC32], [qemu-sparc32plus-static qemu-sparc32plus], [], [$PATH:$HOME/build/qemu-linux-user])
  test -n "$QEMU_SPARC64" || nfw_missing="$nfw_missing qemu-sparc64"
  test -n "$QEMU_SPARC32" || nfw_missing="$nfw_missing qemu-sparc32plus"
  nfw_emu_run() {
    nfw_emu=$1; nfw_bits=$2
    nfw_try '#include <stdio.h>
int main(void) { printf("%d\n", 6 * 7); return 0; }' "$nfw_cross_cc" -static -$nfw_bits -o conftest conftest.c -lm || return 1
    nfw_out=`cd $nfw_probe_dir && "$nfw_emu" ./conftest 2>>../config.log`
    test "$nfw_out" = 42
  }
  if test -n "$QEMU_SPARC64"; then
    AC_CACHE_CHECK([whether $QEMU_SPARC64 runs a static -m64 program], [nfw_cv_emu64], [
      if nfw_emu_run "$QEMU_SPARC64" m64; then nfw_cv_emu64=yes; else nfw_cv_emu64=no; fi])
    test "$nfw_cv_emu64" = yes || nfw_missing="$nfw_missing qemu-sparc64(cannot run a static -m64 program: config.log)"
  fi
  if test -n "$QEMU_SPARC32"; then
    AC_CACHE_CHECK([whether $QEMU_SPARC32 runs a static -m32 program], [nfw_cv_emu32], [
      if nfw_emu_run "$QEMU_SPARC32" m32; then nfw_cv_emu32=yes; else nfw_cv_emu32=no; fi])
    test "$nfw_cv_emu32" = yes || nfw_missing="$nfw_missing qemu-sparc32plus(cannot run a static -m32 program: config.log)"
  fi
  if test -n "$QEMU_SPARC64" && test -n "$QEMU_SPARC32"; then
    nfw_emu64_ver=`"$QEMU_SPARC64" --version 2>/dev/null | head -1`
    nfw_emu32_ver=`"$QEMU_SPARC32" --version 2>/dev/null | head -1`
    AC_MSG_NOTICE([linux-user emulators: $nfw_emu64_ver ($QEMU_SPARC64) / $nfw_emu32_ver ($QEMU_SPARC32)])
  fi
fi

dnl =========================================================================================
dnl  sun
dnl =========================================================================================
SUN_STUDIO=
SUN_CC_LIBCALLS=0
SUN_CC_NODEPEND=no
HV_STABS_PROBE=0
SUN_CC_VERSION=
SUN_PATCH=
SUN_OBJCOPY=
if test "$TOOLCHAIN" = sun; then
  AC_MSG_CHECKING([for the Sun Studio installation])
  if test -n "$with_sun_studio"; then
    # DIR or DIR/bin, with or without trailing slashes (printf: Solaris' sed drops a last line without a newline)
    SUN_STUDIO=`printf '%s\n' "$with_sun_studio" | sed -e 's|//*$||'`
    if test ! -x "$SUN_STUDIO/bin/cc" && test -x "$SUN_STUDIO/cc"; then
      SUN_STUDIO=`printf '%s\n' "$SUN_STUDIO" | sed -e 's|/bin$||'`
    elif test ! -x "$SUN_STUDIO/bin/cc" && test -x "$SUN_STUDIO/SUNWspro/bin/cc"; then
      # an installation prefix (Sun Studio 12 installs into PREFIX/SUNWspro)
      SUN_STUDIO=$SUN_STUDIO/SUNWspro
    fi
    nfw_how="--with-sun-studio"
  else
    # 1. the first cc on PATH that says it is Sun's (so that PATH=/anywhere/bin:$PATH ./configure works)
    nfw_how=
    nfw_ifs=$IFS; IFS=:
    for nfw_d in $PATH; do
      test -n "$nfw_d" || continue
      if test -x "$nfw_d/cc" && "$nfw_d/cc" -V 2>&1 | grep 'Sun C' >/dev/null 2>&1; then
        SUN_STUDIO=`printf '%s\n' "$nfw_d" | sed -e 's|//*$||' -e 's|/bin$||'`
        if test -x "$SUN_STUDIO/bin/cc"; then nfw_how="cc on PATH"; break; fi
        SUN_STUDIO=
      fi
    done
    IFS=$nfw_ifs
    # 2. the places Sun Studio installs by default
    if test -z "$nfw_how"; then
      for nfw_d in /opt/SUNWspro /opt/developerstudio12.6 /opt/developerstudio12.5 \
                   /opt/solarisstudio12.4 /opt/solarisstudio12.3 /opt/sunstudio12.1; do
        if test -x $nfw_d/bin/cc; then SUN_STUDIO=$nfw_d; nfw_how="default location"; break; fi
      done
    fi
  fi
  if test -z "$SUN_STUDIO" || test ! -x "$SUN_STUDIO/bin/cc"; then
    AC_MSG_RESULT([none])
    NFW_FAIL([no cc at ${SUN_STUDIO:-/opt/...}/bin/cc; --with-sun-studio=DIR takes one directory: DIR, DIR/bin or DIR/SUNWspro has the cc (for example /opt/SUNWspro), not a list like PATH; or install Sun Studio])
  fi
  AC_MSG_RESULT([$SUN_STUDIO ($nfw_how)])

  dnl Run the cc itself: Developer Studio 12.5 and 12.6 carry a .SUNW_cap that ld.so.1 refuses on a
  dnl CPU that does not declare VIS (`isainfo -v`), and the message is a bare capability mismatch.
  AC_MSG_CHECKING([whether the cc runs])
  SUN_CC_VERSION=`"$SUN_STUDIO/bin/cc" -V 2>&1 | sed 1q`
  if nfw_try 'int main(void) { return 0; }' "$SUN_STUDIO/bin/cc" -c conftest.c; then
    AC_MSG_RESULT([$SUN_CC_VERSION])
  else
    AC_MSG_RESULT([no])
    NFW_FAIL([$SUN_STUDIO/bin/cc cannot compile (see config.log; cc -V says: $SUN_CC_VERSION). Studio 12.5 and 12.6 need the VIS hwcap: isainfo -v, REQUIREMENTS.SOLARIS])
  fi

  dnl The PROM's Forth engine is a 64-bit program (-xarch=v9): link one. A Studio installed without its
  dnl 64-bit packages has no v9 crti.o (Sun Studio 12.0) or crashes in the linker (12.1).
  AC_MSG_CHECKING([whether the cc links a 64-bit program])
  if nfw_try 'int main(void) { return 0; }' "$SUN_STUDIO/bin/cc" -xarch=v9 -o conftest conftest.c; then
    AC_MSG_RESULT([yes])
  else
    AC_MSG_RESULT([no])
    nfw_missing="$nfw_missing cc(cannot link a 64-bit program, -xarch=v9: install the Studio's 64-bit packages, REQUIREMENTS.SOLARIS; config.log)"
  fi

  PATH=/usr/ccs/bin:/usr/bin:/usr/sbin:$SUN_STUDIO/bin:/usr/sfw/bin:$PATH
  AC_CHECK_PROG([nfw_make_sun], [make], [/usr/ccs/bin/make], [], [/usr/ccs/bin])
  test -n "$nfw_make_sun" || nfw_missing="$nfw_missing /usr/ccs/bin/make"
  nfw_need flex gmake
  AC_PATH_PROGS([SUN_PATCH], [gpatch patch], [], [/usr/bin:/usr/sfw/bin:$PATH])
  AC_MSG_CHECKING([whether $SUN_PATCH is GNU patch])
  if test -n "$SUN_PATCH" && nfw_gnu_patch "$SUN_PATCH"; then
    AC_MSG_RESULT([yes])
  else
    AC_MSG_RESULT([no])
    nfw_missing="$nfw_missing gpatch"
  fi
  AC_PATH_PROG([SUN_OBJCOPY], [gobjcopy], [], [/usr/sfw/bin:$PATH])
  test -n "$SUN_OBJCOPY" || nfw_missing="$nfw_missing gobjcopy(SUNWbinutils)"


  dnl q.bin and openboot.bin are objcopy -O binary of the linked image. Run it, do not just find it.
  if test -n "$SUN_OBJCOPY"; then
    AC_CACHE_CHECK([whether $SUN_OBJCOPY writes -O binary], [nfw_cv_sun_objcopy], [
      if nfw_try 'int f(int x) { return x + 1; }' "$SUN_STUDIO/bin/cc" -c -o conftest.o conftest.c \
         && ( cd $nfw_probe_dir && "$SUN_OBJCOPY" -O binary conftest.o conftest.bin ) >&AS_MESSAGE_LOG_FD 2>&1 \
         && test -s $nfw_probe_dir/conftest.bin; then
        nfw_cv_sun_objcopy=yes
      else
        nfw_cv_sun_objcopy=no
      fi])
    test "$nfw_cv_sun_objcopy" = yes || nfw_missing="$nfw_missing gobjcopy(-O-binary)"
  fi

  dnl The hypervisor needs -xarch=v9d for the hyperprivileged registers, and only /usr/ccs/bin/as from
  dnl SUNWsprot patch 118683-15 on accepts it (REQUIREMENTS.SOLARIS).
  AC_CACHE_CHECK([whether /usr/ccs/bin/as accepts -xarch=v9d], [nfw_cv_sun_as_v9d], [
    rm -rf $nfw_probe_dir; mkdir $nfw_probe_dir
    printf '\trdhpr\t%%hpstate, %%g1\n' > $nfw_probe_dir/conftest.s
    if ( cd $nfw_probe_dir && /usr/ccs/bin/as -xarch=v9d -o conftest.o conftest.s ) >&AS_MESSAGE_LOG_FD 2>&1; then
      nfw_cv_sun_as_v9d=yes
    else
      nfw_cv_sun_as_v9d=no
    fi])
  test "$nfw_cv_sun_as_v9d" = yes || nfw_missing="$nfw_missing as(-xarch=v9d:SUNWsprot-118683-15)"

  dnl Does this cc write stabs? Sun's offsets.h rules need them (Sun Studio 11 .. Studio 12.5 do; Developer
  dnl Studio 12.6 does not: its cc(1) calls -xdebugformat=stabs obsolete). Counts the .stabs type lines;
  dnl the .xstabs index lines every cc writes do not count. 0 sends the build to the DWARF reader.
  AC_CACHE_CHECK([whether the cc writes stabs], [nfw_cv_sun_stabs], [
    dnl a real hypervisor source (mdsup.c: structs, typedefs, enums), compiled the way offsets.h's types are
    if nfw_try_cd "$SUN_STUDIO/bin/cc" -xdebugformat=stabs -g -S -xarch=v9a -KPIC -xO3 $nfw_hv_inc \
         -o conftest.s "$nfw_hv_src/common/src/mdsup.c"; then
      nfw_cv_sun_stabs=`grep -c '\.stabs "' $nfw_probe_dir/conftest.s 2>/dev/null`
    else
      nfw_cv_sun_stabs=0
    fi
    test -n "$nfw_cv_sun_stabs" || nfw_cv_sun_stabs=0])
  HV_STABS_PROBE=$nfw_cv_sun_stabs
  if test "$HV_STABS_PROBE" = 0; then
    AC_MSG_CHECKING([for the DWARF dumper the stabs-less path needs])
    if test -x "$SUN_STUDIO/bin/dwarfdump"; then
      AC_MSG_RESULT([$SUN_STUDIO/bin/dwarfdump])
    else
      AC_MSG_RESULT([no])
      nfw_missing="$nfw_missing $SUN_STUDIO/bin/dwarfdump"
    fi
    nfw_need perl
    AC_CACHE_CHECK([whether offsets.h can be made from this cc's DWARF], [nfw_cv_sun_dwarf], [
      if test -x "$SUN_STUDIO/bin/dwarfdump" && nfw_dwarf_probe "$SUN_STUDIO/bin/cc -xarch=v9a" -g "$SUN_STUDIO/bin/dwarfdump" dwarfdump; then
        nfw_cv_sun_dwarf=yes
      else
        nfw_cv_sun_dwarf=no
      fi])
    test "$nfw_cv_sun_dwarf" = yes || nfw_missing="$nfw_missing dwarf(offsets.h)"
  fi

  dnl Does it rewrite copy and clear loops into calls to _memcpy/_memset (Developer Studio 12.3 and later in
  dnl decomp.c at -fast, 12.6 also in the hypervisor at -xO3)? The hypervisor and the PROM's decomp.o have
  dnl no libc: such a cc is given -xbuiltin=%none through build/cc-nobuiltin.sh (config.mk, SUN_CC_NOBUILTIN).
  dnl Asked of the real sources with the real flags: the four hypervisor files above at -xarch=v9a -KPIC -xO3,
  dnl and the PROM's decomp.c at -fast. Then asked again with the flag, which must make the calls disappear.
  nfw_tab=`printf '\t'`
  nfw_sun_libcalls() {
    nfw_n=0
    for nfw_s in $nfw_hv_probe_srcs; do
      "$SUN_STUDIO/bin/cc" -xarch=v9a -KPIC -xO3 $nfw_hv_inc $1 -S -o conftest.s "$nfw_hv_src/$nfw_s" || return 1
      nfw_k=`egrep -c "(call|jmp)@<:@ $nfw_tab@:>@+_mem(cpy|set)" conftest.s`
      nfw_n=`expr $nfw_n + $nfw_k`
    done
    "$SUN_STUDIO/bin/cc" -DSTANDALONE -fast $1 -S -o conftest.s "$nfw_top/src/obp/tools/decomp.c" || return 1
    nfw_k=`egrep -c "(call|jmp)@<:@ $nfw_tab@:>@+_mem(cpy|set)" conftest.s`
    nfw_n=`expr $nfw_n + $nfw_k`
    echo $nfw_n > libcalls.n
  }
  AC_CACHE_CHECK([whether the cc turns loops into _memcpy/_memset calls], [nfw_cv_sun_libcalls], [
    if nfw_try_cd nfw_sun_libcalls ''; then
      nfw_cv_sun_libcalls=`cat $nfw_probe_dir/libcalls.n`
    else
      nfw_cv_sun_libcalls=failed
    fi])
  case "$nfw_cv_sun_libcalls" in
  failed) nfw_missing="$nfw_missing cc(cannot compile the hypervisor sources or the PROM's decomp.c: config.log)"; nfw_cv_sun_libcalls=0 ;;
  0) ;;
  *) if nfw_try_cd nfw_sun_libcalls -xbuiltin=%none && test "`cat $nfw_probe_dir/libcalls.n`" = 0; then
       :
     elif nfw_try_cd nfw_sun_libcalls "-xbuiltin=%none -xdepend=no" && test "`cat $nfw_probe_dir/libcalls.n`" = 0; then
       dnl Sun Studio 12.2 (cc 5.11): the loop-to-memset rewrite belongs to the dependence analysis there
       SUN_CC_NODEPEND=yes
     else
       nfw_missing="$nfw_missing cc(-xbuiltin=%none does not remove the _memcpy/_memset calls: config.log)"
     fi ;;
  esac
  SUN_CC_LIBCALLS=$nfw_cv_sun_libcalls
fi
rm -rf $nfw_probe_dir

if test -n "$nfw_missing"; then
  NFW_FAIL([missing or unusable:$nfw_missing -- see REQUIREMENTS.LINUX / REQUIREMENTS.SOLARIS])
fi

dnl nfw_tilde WORD: a leading ~ or ~user, which a shell does not expand in --with-outdir=~/x, as the
dnl home directory (getent: Solaris 10 has it; an unknown user leaves the word as it is). No sed
dnl brackets here: m4 eats them.
nfw_tilde() {
  case "$1" in
  "~"|"~/"*) nfw_th=$HOME; nfw_tu= ;;
  "~"*) nfw_tu=`printf '%s' "$1" | cut -d/ -f1 | cut -c2-`; nfw_th=`getent passwd "$nfw_tu" 2>/dev/null | cut -d: -f6` ;;
  *) printf '%s\n' "$1"; return 0 ;;
  esac
  if test -z "$nfw_th"; then printf '%s\n' "$1"; return 0; fi
  case "$1" in
  */*) nfw_tr=/`printf '%s' "$1" | cut -d/ -f2-` ;;
  *) nfw_tr= ;;
  esac
  printf '%s\n' "$nfw_th$nfw_tr"
}

dnl --- what config.auto.mk says ------------------------------------------------------------
dnl A line is written only for the branch that was configured (a leading # comments the other one
dnl out), and OUTDIR only when asked for: everything else stays config.mk's default.
if test "$TOOLCHAIN" = gnu; then GNU_ON=; SUN_ON='#'; else GNU_ON='#'; SUN_ON=; fi
if test -n "$with_outdir"; then OUTDIR_ON=; OUTDIR=`nfw_tilde "$with_outdir"`
elif test "$nfw_oot" = yes; then OUTDIR_ON=; OUTDIR=$nfw_builddir/output
else OUTDIR_ON='#'; OUTDIR=; fi
if test -n "$with_workdir"; then WORKDIR_ON=; WORKDIR=`nfw_tilde "$with_workdir"`; else WORKDIR_ON='#'; WORKDIR=; fi
if test -z "$OUTDIR_ON"; then nfw_eff_out=$OUTDIR; else nfw_eff_out=$nfw_top/output; fi
nfw_wd_shown=`cd "$nfw_top" && sh build/workdir.sh path "$nfw_eff_out" "$WORKDIR"`
if test -n "$GNU_CSTD"; then CSTD_ON=; else CSTD_ON='#'; fi
if test -n "$HOST_CSTD"; then HCSTD_ON=; else HCSTD_ON='#'; fi
case "$enable_hv_uart" in
yes) HVUART_ON=; HV_UART=yes ;;
no)  HVUART_ON='#'; HV_UART=no ;;
*)   NFW_FAIL([--enable-hv-uart takes no argument other than yes or no]) ;;
esac
dnl --with-target: checked against the md/*/1up.pdesc that are there, the same discovery config.mk does,
dnl so a configuration taken out of the tree stops being accepted without touching this file.
if test -n "$with_target"; then
  nfw_mdlist=
  for nfw_f in "$nfw_top"/md/*/1up.pdesc; do
    test -f "$nfw_f" || continue
    nfw_n=`echo "$nfw_f" | sed -e 's|/1up.pdesc$||' -e 's|.*/||'`
    nfw_mdlist="$nfw_mdlist $nfw_n"
  done
  if test -z "$nfw_mdlist"; then NFW_FAIL([--with-target: no md/*/1up.pdesc in this tree]); fi
  nfw_ok=no
  for nfw_n in all $nfw_mdlist; do
    if test "$with_target" = "$nfw_n"; then nfw_ok=yes; fi
  done
  if test "$nfw_ok" != yes; then NFW_FAIL([--with-target=$with_target: not one of: all$nfw_mdlist]); fi
  MDCFG_ON=; TARGET=$with_target
else
  MDCFG_ON='#'; TARGET=
fi
dnl --with-md-mem: whole MB, no leading zero (make would read it as is, cpp as octal), at most 9 digits.
dnl Outside 1024..32768 only warns: those are the sizes measured, not a limit the firmware enforces.
if test -n "$with_md_mem"; then
  case "$with_md_mem" in
  *@<:@!0-9@:>@*|0*|??????????*)
    NFW_FAIL([--with-md-mem=$with_md_mem: a whole number of MB, no leading zero (for example 4096)]) ;;
  esac
  if test "$with_md_mem" -lt 1024 || test "$with_md_mem" -gt 32768; then
    AC_MSG_WARN([--with-md-mem=$with_md_mem is outside 1024..32768 MB, the range that was tested])
  fi
  MDMEM_ON=; MD_MEM=$with_md_mem
else
  MDMEM_ON='#'; MD_MEM=
fi
AC_SUBST([MDCFG_ON])
AC_SUBST([TARGET])
AC_SUBST([MDMEM_ON])
AC_SUBST([MD_MEM])
AC_SUBST([TOOLCHAIN])
AC_SUBST([nfw_top])
AC_SUBST([nfw_builddir])
AC_SUBST([GNU_ON])
AC_SUBST([SUN_ON])
AC_SUBST([OUTDIR_ON])
AC_SUBST([CSTD_ON])
AC_SUBST([HCSTD_ON])
AC_SUBST([HVUART_ON])
AC_SUBST([HV_UART])
AC_SUBST([OUTDIR])
AC_SUBST([WORKDIR_ON])
AC_SUBST([WORKDIR])
AC_SUBST([GNU_CROSS_BIN])
AC_SUBST([GNU_CSTD])
AC_SUBST([HOST_GCC])
AC_SUBST([HOST_CSTD])
AC_SUBST([nfw_host_version])
AC_SUBST([QEMU_SPARC64])
AC_SUBST([QEMU_SPARC32])
AC_SUBST([nfw_cross_version])
AC_SUBST([SUN_STUDIO])
AC_SUBST([SUN_CC_VERSION])
AC_SUBST([SUN_CC_LIBCALLS])
AC_SUBST([SUN_CC_NODEPEND])
AC_SUBST([HV_STABS_PROBE])
AC_SUBST([SUN_PATCH])
AC_SUBST([SUN_OBJCOPY])
AC_OUTPUT

echo
echo "configured: toolchain $TOOLCHAIN, written to config.auto.mk"
if test "$TOOLCHAIN" = gnu; then
  echo "  cross gcc   $nfw_cross_version; ${GNU_CSTD:-default language level}"
  echo "  as, ld      `sparc64-linux-gnu-as --version | sed 1q`; `sparc64-linux-gnu-ld --version | sed 1q`"
  echo "  host gcc    $nfw_host_version; ${HOST_CSTD:-default language level} (mdgen, mdlint)"
else
  echo "  cc          $SUN_CC_VERSION"
  if test "$HV_STABS_PROBE" = 0; then echo "  stabs       no: offsets.h from DWARF"; else echo "  stabs       yes"; fi
  if test "$SUN_CC_LIBCALLS" = 0; then echo "  libcalls    no"; else if test "$SUN_CC_NODEPEND" = yes; then echo "  libcalls    yes: cc -xbuiltin=%none -xdepend=no"; else echo "  libcalls    yes: cc -xbuiltin=%none"; fi; fi
fi
if test "$HV_UART" = yes; then
  echo "  hv console  ON: the firmware needs a QEMU with the niagara-hvuart-console patch (github.com/unix0cc/qemu-experimental-patches, devel/), else it hangs"
fi
if test -n "$TARGET"; then echo "  target      $TARGET"; fi
if test -n "$MD_MEM"; then echo "  guest RAM   $MD_MEM MB: run QEMU with -m $MD_MEM"; fi
if test -z "$OUTDIR_ON" && test -n "$OUTDIR"; then echo "  output      $OUTDIR"; fi
echo "  work dir    $nfw_wd_shown"
if test "$TOOLCHAIN" = sun; then nfw_mk=gmake; else nfw_mk=make; fi
echo "next: $nfw_mk config (what will be built), $nfw_mk, $nfw_mk test (smoke)"
