/*
 * Linker script for R9.
 */

ENTRY(start)

SECTIONS {
	/*
	 * start the kernel at 0x0xffff_8000_0020_0000
	 * This preserves some RAM between 1MiB and the
	 * start of the kernel for critical structures.
	 */
	. = ${LOAD-ADDRESS};

	PROVIDE(text = .);
	.text : ALIGN(4096) {
		*(.text.boot)
		*(.*text* .stub .gnu.linkonce.t.*)
		. = ALIGN(4096);
		*(.trap*)
		. = ALIGN(2097152);
		PROVIDE(etext = .);
	}

	.rodata : ALIGN(4096) {
		*(.*rodata* .gnu.linkonce.r.*)
		. = ALIGN(2097152);
		PROVIDE(erodata = .);
	}

	.data : ALIGN(4096) {
		*(.*data*)
	}
	.got : ALIGN(4096) {
		*(.got)
	}
	.got.plt : ALIGN(4096) {
		*(.got.plt)
	}
	PROVIDE(edata = .);

	.bss : ALIGN(4096) {
		*(COMMON)
		*(.*bss*)
		. = ALIGN(2097152);
	}
	PROVIDE(end = .);

	/DISCARD/ : {
		*(.eh_frame* .note*)
	}
}
