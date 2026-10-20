/*
 * ========== Copyright Header Begin ==========================================
 *
 * Hypervisor Software File: openboot.map
 *
 * Copyright (c) 2006 Sun Microsystems, Inc. All Rights Reserved.
 *
 *  - Do no alter or remove copyright notices
 *
 *  - Redistribution and use of this software in source and binary forms, with
 *    or without modification, are permitted provided that the following
 *    conditions are met:
 *
 *  - Redistribution of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 *  - Redistribution in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 *    Neither the name of Sun Microsystems, Inc. or the names of contributors
 * may be used to endorse or promote products derived from this software
 * without specific prior written permission.
 *
 *     This software is provided "AS IS," without a warranty of any kind.
 * ALL EXPRESS OR IMPLIED CONDITIONS, REPRESENTATIONS AND WARRANTIES,
 * INCLUDING ANY IMPLIED WARRANTY OF MERCHANTABILITY, FITNESS FOR A
 * PARTICULAR PURPOSE OR NON-INFRINGEMENT, ARE HEREBY EXCLUDED. SUN
 * MICROSYSTEMS, INC. ("SUN") AND ITS LICENSORS SHALL NOT BE LIABLE FOR
 * ANY DAMAGES SUFFERED BY LICENSEE AS A RESULT OF USING, MODIFYING OR
 * DISTRIBUTING THIS SOFTWARE OR ITS DERIVATIVES. IN NO EVENT WILL SUN
 * OR ITS LICENSORS BE LIABLE FOR ANY LOST REVENUE, PROFIT OR DATA, OR
 * FOR DIRECT, INDIRECT, SPECIAL, CONSEQUENTIAL, INCIDENTAL OR PUNITIVE
 * DAMAGES, HOWEVER CAUSED AND REGARDLESS OF THE THEORY OF LIABILITY,
 * ARISING OUT OF THE USE OF OR INABILITY TO USE THIS SOFTWARE, EVEN IF
 * SUN HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
 *
 * You acknowledge that this software is not designed, licensed or
 * intended for use in the design, construction, operation or maintenance of
 * any nuclear facility.
 *
 * ========== Copyright Header End ============================================
 *
 * This file is a translation of Sun's linker mapfile (src/obp/obp/arch/sun4u/openboot.map, above); Sun's notice and licence
 * (BSD+_License_OpenSPARCT2.txt) apply to it. What this project added to it is BSD-2-Clause (LICENSE_CODE).
 */
/*
 * openboot.ld -- GNU ld translation of src/obp/obp/arch/sun4u/openboot.map.
 * Validated: used unmodified across every reset.bin built with it, both
 * machine configs, each accepted by build/obp/verify-dropin-chain.sh and
 * boot-tested to the OpenBoot banner and beyond.
 *
 * Sun's mapfile:
 *   note = NOTE; note : $NOTE ; note : .comment ; note : .stab.index ;
 *   ram = LOAD ?RWO V0x40000; ram : .bss ;
 *   rom = LOAD ?RX V0x0; rom : .text ; rom : $PROGBITS ; rom : $NOBITS ; rom : .data ; rom : .data1 ;
 *
 * Measured from the reference's own unstripped reset.elf (readelf -S/-l,
 * 2026-09-19): the "$PROGBITS" wildcard sweeps in .debug_info/.debug_line/
 * .debug_abbrev too (Sun cc emits these even under -fast with no -g,
 * xdbggen=no%stabs+dwarf2+usedonly), which is why .text's real address in
 * the reference's link is 0x17c, not 0x0 -- they are placed first, in that
 * order. Reproduced here explicitly rather than left to input order.
 *
 * .ram / COMMON order (2026-09-20, mixed link): with the reference's
 * own decomp.o linked by GNU ld, reset.bin differed from the reference's in 70
 * bytes, every one of them a sethi/or immediate for one of decomp.o's six
 * COMMON symbols -- Sun ld and GNU ld allocate tentative definitions in .bss
 * in a different order, and GNU ld has no option to reproduce Sun's (it is
 * neither declaration, .symtab, size nor alignment order). Relinking with
 * --defsym at Sun's addresses gave a byte-identical reset.bin, so the order
 * is the whole of the difference. It is pinned below by defining the six
 * symbols in the script in Sun's order (a script definition overrides a
 * common), with sizes from tools/decomp.c (HSIZE = 18013: tab_suffix
 * char[HSIZE], tab_prefix unsigned short[HSIZE], de_stack char[8000],
 * input/output/data_count int). decomp.c is frozen Sun source, never edited
 * here; the ASSERT catches a name or total-size drift all the same. Nothing
 * functional depends on this order -- both layouts are correct programs; it
 * exists so the GNU link is the reference's link, not merely an equivalent one.
 */
ENTRY(reset)
SECTIONS
{
    . = 0x0;
    .rom : {
        *(.debug_info)
        *(.debug_line)
        *(.debug_abbrev)
        *(.text)
        *(.rodata*)
        *(.data)
        *(.data1)
    }
    . = 0x40000;
    .ram (NOLOAD) : {
        *(.bss)                          /* decomp.o's own: 8 bytes */
        . = ALIGN(4);  input      = . ;  . += 4;
        . = ALIGN(2);  tab_prefix = . ;  . += 36026;
                       tab_suffix = . ;  . += 18013;
        . = ALIGN(4);  data_count = . ;  . += 4;
        . = ALIGN(4);  output     = . ;  . += 4;
                       de_stack   = . ;  . += 8000;
        *(COMMON)
    }
    /* Sun ld's _end for this input set; anything left for *(COMMON) above
       (a renamed or resized decomp.c symbol) moves it and trips this. */
    ASSERT(SIZEOF(.ram) == 0xf26c, "openboot.ld: .ram layout no longer matches Sun's (see COMMON note)")
    /DISCARD/ : {
        *(.comment)
        *(.stab*)
        *(.note*)
    }
}
