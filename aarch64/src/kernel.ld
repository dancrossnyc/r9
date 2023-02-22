/*
 * Linker script for R9.
 */

ENTRYPOINT = 0x80000;
KOFFSET = 0xffff800000000000;

ENTRY(start)

SECTIONS {
	/*
	 * Raspberry Pi start address (ENTRYPOINT) is 0x80_0000, but we want the
	 * kernel to be linked in the higher half, starting at KOFFSET + 2MiB.
	 */

	/* .text.boot is linked at 0x80_0000, with the end aligned to 2MiB, so
	 * that when we increment by KOFFSET, the main kernel .text section is
	 * at 0xffff_8000_0020_0000, consistent with other architectures.
	 */
	. = ENTRYPOINT;

	PROVIDE(boottext = .);
	.text.boot : ALIGN(4096) {
		*(.boottext .bootdata)
		. = ALIGN(4096);
		PROVIDE(eboottext = .);
		. = ALIGN(2097152);
		PROVIDE(esys = .);
	}

	/* All sections from this point have virtual addresses in the higher half,
	 * but have load addresses immediately following the preceeding sections.
	 * The key is `AT (ADDR (.xxx) - KOFFSET)` which ensures that although the
	 * virtual addresses are in the high half, the load addresses remain
	 * consecutive.
	 */
	. += KOFFSET;

	PROVIDE(text = .);
	.text ALIGN(4096) : AT (ADDR (.text) - KOFFSET) {
		*(.text* .stub .gnu.linkonce.t.*)
		. = ALIGN(2097152);	
		PROVIDE(etext = .);
	}

	.rodata ALIGN(4096) : AT (ADDR (.rodata) - KOFFSET) {
		*(.rodata* .gnu.linkonce.r.*)
		. = ALIGN(2097152);
		PROVIDE(erodata = .);
	}

	.data ALIGN(4096) : AT (ADDR (.data) - KOFFSET) {
		*(.data*)
	}
	.got ALIGN(4096) : AT (ADDR (.bss) - KOFFSET) {
		*(.got)
	}
	.got.plt ALIGN(4096) : AT (ADDR (.bss) - KOFFSET) {
		*(.got.plt)
	}
	PROVIDE(edata = .);

	PROVIDE(bss = .);
	.bss ALIGN(4096) : AT (ADDR (.bss) - KOFFSET) {
		*(.bss*)
		*(COMMON)
		. = ALIGN(2097152);
	}
	PROVIDE(end = .);

	/DISCARD/ : {
		*(.eh_frame .note.GNU-stack)
	}
}
