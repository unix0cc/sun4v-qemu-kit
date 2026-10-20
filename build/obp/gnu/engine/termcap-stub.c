/*
 * termcap-stub.c -- build-layer replacement for src/obp/obp/os/unix/termcap.c.
 *
 * Not a patch to Sun's source: termcap.c is simply not compiled into the
 * GNU-path engine, this file is linked in its place. It implements exactly
 * the four functions wrapper.h declares (t_init/t_rows/t_cols/t_op) and
 * nothing else -- termcap.c's t_move is undeclared in wrapper.h and unused
 * outside termcap.c itself (grep confirms), so it is not reproduced.
 *
 * Why a stub is correct here, not a workaround: every .fth in the tree was
 * grepped for a dependency on real terminal capabilities and found to have
 * none. t_init() is reached only if the dictionary asks for it, and no
 * build-time .fth does -- every build invocation of `forth` is already
 * non-interactive (-s "..." scripts; fileques() sees a non-tty stdin). If a
 * future use of this engine needs real terminal handling for an
 * *interactive* boot-prompt style session (not a build step), replace this
 * file with a cross-built libtinfo/libncurses termcap.c, not by patching
 * this stub.
 */
#include <stdio.h>

int
t_init(void)
{
	return (0);
}

int
t_rows(void)
{
	return (24);
}

int
t_cols(void)
{
	return (80);
}

void
t_op(int op)
{
	(void) op;
}
