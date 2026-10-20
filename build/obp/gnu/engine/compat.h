/*
 * compat.h -- force-included (gcc -include) when cross-compiling src/obp's
 * engine (wrapper.c/fsys.c) and host tools (didepend.c/makedi.c/comp.c/
 * makeprom.c/checksum.c/crc32.c) for a modern GNU toolchain. Not a patch to
 * any of Sun's source -- every mapping here is a missing standard header or
 * a Solaris-only typedef these files rely on <sys/types.h> to provide
 * implicitly on Solaris.
 */
#ifndef _OBP_GNU_COMPAT_H_
#define _OBP_GNU_COMPAT_H_

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>	/* getopt(3), for didepend.c */

/* Solaris <sys/types.h> extensions sys/dropins.h and the engine both use,
 * not provided by glibc. */
typedef unsigned char uchar_t;
typedef unsigned short ushort_t;
typedef unsigned int uint_t;
typedef unsigned long ulong_t;

/*
 * sigset(3C): NOT mapped here any more. A `#define sigset(...) signal(...)`
 * used to sit here and never took effect -- wrapper.c's own SYS5 branch
 * #defines signal to sigset AFTER this header, and the preprocessor will not
 * re-expand a macro inside its own expansion, so every call still resolved
 * to an undeclared sigset(). patches/obp/gnu/engine-tools-c99-decls.patch
 * skips wrapper.c's #define on Linux instead; the reasoning about signal(2)
 * being equivalent for these calls is in that patch's header.
 */

/*
 * checksum()/crc32() (tools/checksum/{checksum,crc32}.c) are called from
 * makeprom.c with no prototype in scope anywhere in the source -- an
 * implicit declaration on a 64-bit host silently corrupts the argument
 * ABI. Real signatures, read directly from the .c files.
 */
extern uint16_t checksum(uint16_t *addr, int32_t count);
extern uint32_t crc32(int bufsiz, uchar_t *bufptr, uint32_t seed);

/*
 * Pointer-safe replacement for sys/dropins.h's ROUNDUP(n), which casts
 * through (unsigned int) -- correct only on the 32-bit ABI these tools were
 * always built for. makeprom.c's own two pointer-rounding call sites are
 * patched (patches/obp/gnu/makeprom-ptr-roundup.patch) to use this instead of
 * ROUNDUP() when rounding a pointer, not a size. Root-caused via
 * gdb-multiarch on qemu-sparc64's gdbstub.
 */
#define PTR_ROUNDUP(p) ((void *)(((uintptr_t)(p) + 3) & ~(uintptr_t)3))

#endif /* _OBP_GNU_COMPAT_H_ */
