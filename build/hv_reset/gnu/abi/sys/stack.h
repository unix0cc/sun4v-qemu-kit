/*
 * sys/stack.h -- SPARC V9 stack frame constants, from the primary
 * specification rather than from an operating system's kernel headers.
 *
 * Replaces a CDDL-licensed file (illumos-gate usr/src/uts/sparc/sys/stack.h)
 * that this build previously vendored for exactly four symbols: V9BIAS64,
 * STACK_BIAS, MINFRAME and SA(). None of them are illumos's to license --
 * they are the 64-bit stack-frame layout defined by the platform ABI, which
 * every SPARC V9 System V implementation (Solaris and otherwise) must use
 * identically to interoperate at the binary level. Solaris did not invent
 * these numbers; it implements them.
 *
 * Source: SPARC Compliance Definition 2.4.1 ("SCD 2.4.1", SPARC
 * International, 1999), Chapter 3 "Low-Level System Information",
 * section 3P-8, Figure 3-16 "Standard Stack Frame" and the accompanying
 * text and Figure 3-17.
 *
 *   - Stack bias: "The stack pointer is offset from the stack frame by a
 *     BIAS of 2047 (0x7ff)." The bias is odd by design -- SCD 2.4.1 notes
 *     this lets a trap handler tell a 64-bit register window from a 32-bit
 *     one by the low bit of %sp alone.
 *   - Frame alignment: "Every stack frame must be 16-byte aligned."
 *   - Minimum frame size: Figure 3-16 lays out 128 bytes for the 16
 *     extended-word register-window save area (offsets 0-127) directly
 *     below 48 bytes for 6 extended-word argument slots (offsets 128-175);
 *     Figure 3-17's own worked example allocates the sum with
 *     "save %sp, -176, %sp". 128 + 48 = 176.
 *
 * This file defines only the four symbols the hypervisor source actually
 * references (checked against every file the ontario/legion GNU build
 * compiles): V9BIAS64, STACK_BIAS, MINFRAME, SA(). The illumos original
 * defines a wider set (WINDOWSIZE32, ARGPUSH64, IS_V9STACK, ...) for its own
 * kernel's use; this build never reaches any of them, so they are not
 * reproduced here -- there is nothing to derive them from without going
 * back to illumos, and nothing here needs them.
 */

#ifndef _SYS_STACK_H
#define	_SYS_STACK_H

#ifdef	__cplusplus
extern "C" {
#endif

/*
 * SCD 2.4.1 SS3P-8: "The stack pointer is offset from the stack frame by a
 * BIAS of 2047 (0x7ff)."
 */
#define	V9BIAS64	2047
#define	STACK_BIAS	V9BIAS64

/*
 * SCD 2.4.1 SS3P-8, Figure 3-16: 128-byte register-window save area
 * (offsets 0-127) plus 48-byte argument-slot area (offsets 128-175);
 * Figure 3-17: "save %sp, -176, %sp".
 */
#define	MINFRAME	176

/*
 * SCD 2.4.1 SS3P-8: "Every stack frame must be 16-byte aligned."
 */
#define	STACK_ALIGN	16
#define	SA(x)		(((x) + (STACK_ALIGN - 1)) & ~(STACK_ALIGN - 1))

#ifdef	__cplusplus
}
#endif

#endif	/* _SYS_STACK_H */
