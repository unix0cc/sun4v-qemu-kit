/*
 * harness.c -- freestanding driver for tools/decomp.c's decompress(), to
 * run the SAME decomp.o the PROM runs (ours, or the reference's Sun-cc one)
 * under qemu-sparc32plus on real dropin payloads. Phase 6 / equivalence
 * tests: "gcc vs cc codegen differs" becomes "…and produces identical output
 * on every payload in the image".
 *
 * Mirrors arch/sun/reset-dropin.fth:131-153 exactly: payload = COMP magic,
 * comp size, COMP, uncompressed size, then data; the PROM calls
 * decompress(payload+0x10, comp_size, dest) and takes the produced length
 * from the global `output` afterwards. So do we.
 *
 * No libc (there is no 32-bit sparc sysroot here -- the whole reason for
 * route B), so: read stdin, write stdout, exit, all via `ta 0x10`.
 * stdin: one record payload (the .di minus its 32-byte OBMD header).
 * stdout: the decompressed bytes. exit status: 0 ok, 2 not COMP, 3 too big.
 */
typedef unsigned int u32;
extern int decompress(unsigned char *ip, int insize, unsigned char *op);
extern unsigned char *output;

static long sys3(long nr, long a, long b, long c)
{
    register long g1 __asm__("g1") = nr;
    register long o0 __asm__("o0") = a;
    register long o1 __asm__("o1") = b;
    register long o2 __asm__("o2") = c;
    __asm__ volatile("ta 0x10" : "+r"(o0) : "r"(g1), "r"(o1), "r"(o2) : "memory", "cc");
    return o0;
}
#define SYS_exit  1
#define SYS_read  3
#define SYS_write 4

static unsigned char inbuf[1 << 19];     /* 512 KiB: bootprom.di is ~215 KiB */
static unsigned char outbuf[1 << 20];    /* 1 MiB: bootprom.bin is ~420 KiB */

static u32 be32(const unsigned char *p) { return (u32)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }

static void writeall(const unsigned char *p, long n)
{
    while (n > 0) { long w = sys3(SYS_write, 1, (long)p, n); if (w <= 0) sys3(SYS_exit, 4, 0, 0); p += w; n -= w; }
}

void _start_c(void)
{
    long n = 0, r;
    while ((r = sys3(SYS_read, 0, (long)(inbuf + n), sizeof inbuf - n)) > 0) n += r;
    if (n < 16 || be32(inbuf) != 0x434f4d50u) sys3(SYS_exit, 2, 0, 0);
    u32 csize = be32(inbuf + 4), usize = be32(inbuf + 12);
    if (usize > sizeof outbuf) sys3(SYS_exit, 3, 0, 0);
    decompress(inbuf + 0x10, (int)csize, outbuf);
    writeall(outbuf, output - outbuf);
    sys3(SYS_exit, 0, 0, 0);
}

/* entry: give C a proper register window and stack frame, then never return */
__asm__(".text\n.globl _start\n_start:\n\tsave %sp, -96, %sp\n\tcall _start_c\n\t nop\n\tta 0x10\n");
