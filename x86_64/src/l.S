// Position independent code for early boot.
//
// It gets ugly to try to link this at some low address
// and then have the rest of the kernel linked high; that
// goes doubly for any attempt to load at a random address.

// Useful definitions.
.set GdtNULL,			(0<<3)
.set GdtCODE64,			(1<<3)
.set GdtCODE32,			(2<<3)
.set GdtDATA32,			(3<<3)

.set SegREAD,			(1<<41)
.set SegWRITE,			(1<<42)
.set SegCODE,			(1<<43)
.set SegDATA,			(0<<43)
.set SegMB1,			(1<<44)
.set SegPRESENT,		(1<<47)
.set SegLONG,			(1<<53)

.set Seg32DEFAULT,		(1<<54)
.set Seg32GRAN,			(1<<55)
.set Seg32LIMIT,		((0xF<<48)+0xFFFF)
.set Seg32DEF,			(Seg32DEFAULT|Seg32GRAN|Seg32LIMIT)

.set MULTIBOOT_FLAG_PGALIGN,	(1<<0)
.set MULTIBOOT_FLAG_MEMINFO,	(1<<1)
.set MULTIBOOT_MAGIC,		0x1BADB002
.set MULTIBOOT_FLAGS,		(MULTIBOOT_FLAG_PGALIGN | MULTIBOOT_FLAG_MEMINFO)
.set MULTIBOOT_CHECKSUM,	-(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS)

.set KiB,			(1<<10)
.set MiB,			(1<<20)
.set GiB,			(1<<30)

.set PGSZ,			(4*KiB)

.set KZERO,			0xffff800000000000
.set KSYS,			(MiB)
.set KTOFF,			(2*MiB)
.set KMACH,			(KTOFF-(4*64*KiB))

.set MACHSTKSZ,			(16*PGSZ)
.set MACHSTKOFF,		(16*PGSZ)
.set MACHGDTSZ,			(16*PGSZ)
.set MACHGDTOFF,		(32*PGSZ)

.set Cr0PE,			(1<<0)		// Protected Mode Enable
.set Cr0MP,			(1<<1)		// Monitor Coprocessor
.set Cr0TS,			(1<<7)		// Task Switched
.set Cr0WP,			(1<<16)		// Write Protect
.set Cr0NW,			(1<<29)		// Not Writethrough
.set Cr0CD,			(1<<30)		// Cache Disable
.set Cr0PG,			(1<<31)		// Paging Enable

.set Cr4PSE,			(1<<4)		// Page-Size Extensions
.set Cr4PAE,			(1<<5)		// Physical Address Extension
.set Cr4PGE,			(1<<7)		// Page-Global Enable

.set IA32_EFER,			0xc0000080	// Extended Feature Enable

.set EferSCE,			(1<<0)		// System Call Extension
.set EferLME,			(1<<8)		// Long Mode Enable
.set EferNXE,			(1<<11)		// No-Execute Enable

.set PteP,			(1<<0)		// Present
.set PteRW,			(1<<1)		// Read/Write
.set PtePS,			(1<<7)		// Page Size
.set PteHiNX,			(1<<31)		// NX in the bit 4 bytes of PTE

// When we get here we are in protected mode with a GDT.  We set
// up IA32e mode and get into long mode with paging enabled, then
// jump to Rust.
//
// This code is thus responsible for setting up the parts of the
// Mach required to get us into Rust code, running against our linked
// addresses.  This means setting up the parts of the Mach required
// for initial entry into Rust code, and in particular hand-crafting
// the initial page tables for early boot (the space for which are
// in the Mach).
//
// The initial page tables provide an (nearly) identity mapping for the first
// 0-4GiB of physical address space to
// KZERO, in addition to an identity map
// for the switch from protected to paged mode.  There
// is an assumption here that the creation and later
// removal of the identity map will not interfere with
// the KZERO mappings.
//
// The bulk of Mach[0] initialization, including remapping the
// kernel and setting up most of the architecturally required
// state, happens in Rust code.  We just do page tables and set
// up the stack here.
//
// Note that this code relies on details of the layout of the
// Mach.
.balign 4096
.section .text.boot, "ax"

.code32
.globl start
start:
	jmp	1f	// Jump over the multiboot header
	// Multiboot 1 header.
	.balign 8
	.long	MULTIBOOT_MAGIC
	.long	MULTIBOOT_FLAGS
	.long	MULTIBOOT_CHECKSUM
1:
	cli
	cld

	// Save the multiboot information pointer.
	movl	%ebx, %ebp

	// Zero the second mibibyte of RAM.  This region holds
	// the Mach for core 0, which in turn holds space for the
	// various architecturally defined state required
	//
	// We could zero the BSS here, but the loader does it for us.
	movl	$KSYS, %edi
	movl	$(KTOFF-KSYS), %ecx
	xorl	%eax, %eax
	rep stosb

	// Load the physical address of the Mach into the base register
	movl	$KMACH, %ebx

	// Load the stack pointer
	leal	MACHSTKOFF+MACHSTKSZ(%ebx), %esp

	// The PML4 lies one page into the Mach.  Load it into the
	// destination register, stash it into %cr3 (note that paging
	// is still disabled) and set up the self-referential pointer.
	leal	PGSZ(%ebx), %edi		// The PML4 is at offset 4096
	movl	%edi, %cr3
	leal	PteRW|PteP(%edi), %edx		// Create the self-ref PTE
	movl	%edx, PGSZ-8(%edi)		// Stash it in the PML4
	movl	$PteHiNX, PGSZ-4(%edi)		// Set the NX bit here

	// The PML3 is on the next page; store pointers to it in the expected
	// locations for the identity and high mapping.
	addl	$PGSZ, %edx
	movl	%edx, (%edi)
	movl	%edx, PGSZ/2(%edi)

	// We also need an identity mapping for when we turn on paging.  We
	// steal a page at KSYS to create that mapping.  This is what we store

	// Now write the PML3 so that it maps the first 4GiB.  The first GiB
	// is covered by a PML2 that lies on the next page byond the PML3.  We
	// use 1GiB "huge" pages for the second, third, and fourth GiB, and map
	// them non-executable.
	leal	PGSZ(%edi), %edi
	addl	$PGSZ, %edx
	movl	%edx, 0(%edi)
	movl	$(GiB|PtePS|PteRW|PteP), %edx
	movl	%edx, 8(%edi)
	movl	$PteHiNX, 12(%edi)
	addl	$GiB, %edx
	movl	%edx, 16(%edi)
	movl	$PteHiNX, 20(%edi)
	addl	$GiB, %edx
	movl	%edx, 24(%edi)
	movl	$PteHiNX, 28(%edi)

	// The PML2 that covers the first 1GiB of physical address space lies
	// at the page immediately beyond the PML3.
	//
	// The first PML2 entry points to a PML1 that covers the first 2MiB of
	// address space.  That PML1 is on the page immediately after the PML2.
	// The next PML2 entry points to the kernel text; the one after to the
	// kernel read-only data, and then beyond that to normal read/write
	// memory, including the kernel's writeable data and BSS.
	leal	PGSZ(%edi), %edi
	leal	PGSZ|PteRW|PteP(%edi), %edx
	movl	%edx, (%edi)
	movl	$(KTOFF|PtePS|PteP), %edx	// Kernel text.
	movl	%edx, 8(%edi)
	addl	$(2*MiB), %edx			// Kernel .rodata
	movl	%edx, 16(%edi)
	movl	$PteHiNX, 20(%edi)		// Set NX bit for data

	// Now map out the rest of the GiB with R/W, NX memory pages.
	orl	$PteRW, %edx
	addl	$24, %edi
	movl	$(PGSZ/8-3), %ecx
1:	addl	$(2*MiB), %edx
	movl	%edx, (%edi)
	movl	$PteHiNX, 4(%edi)
	addl	$8, %edi
	subl	$1, %ecx
	jnz	1b

	// %edi now points to the PML1 in the Mach.  We fill it in so that
	// it maps the first 2MiB of RAM.
	movl	$(PteRW|PteP), %edx
	movl	$(PGSZ/8), %ecx
1:	movl	%edx, (%edi)
	movl	$PteHiNX, 4(%edi)
	addl	$8, %edi
	addl	$PGSZ, %edx
	subl	$1, %ecx
	jnz	1b

	// Note that the Mach lives in the region between 1 and 2MiB,
	// that we just mapped, but it is special: it has holes, and
	// repeated PTE.  Most of it remains in bijection with physical
	// memory (at least, for CPU0's Mach), but the zero page is R/O and
	// we clear some PTEs that are padded in the structure, as this gives
	// us stack guards and similar things.  Also, the GDT is padded out
	// to 64KiB with R/O references to the zero page; only the first page
	// of it is writeable.
	subl	$(PGSZ/8), %edi		// %edi points to start of Mach PTE
	movl	6*8(%edi), %edx		// Load PTE of zero page
	andl	$(~PteRW), %edx		// Clear W bit for zero page
	movl	%edx, 6*8(%edi)
	movl	$0, 7*8(%edi)		// Clear PTE after zero page
	movl	$0, 7*8+4(%edi)
	movl	$0, 9*8(%edi)		// Clear PTE after DF stack
	movl	$0, 9*8+4(%edi)
	movl	$0, 11*8(%edi)		// Clear PTE after DB stack
	movl	$0, 11*8+4(%edi)
	// Clear PTE after NMI stack until beginning of kernel stack.
	movl	$0, 13*8(%edi)
	movl	$0, 13*8+4(%edi)
	movl	$0, 14*8(%edi)
	movl	$0, 14*8+4(%edi)
	movl	$0, 15*8(%edi)
	movl	$0, 15*8+4(%edi)
	// The kernel stack occupies the next 64 KiB, and is followed
	// by the GDT.  But only the first page in the GDT is used; the
	// remaining pages, up to the page GDT, all point to the zero page.
	addl	$(MACHGDTOFF/PGSZ*8), %edi
	movl	%edx, 8*1(%edi)
	movl	%edx, 8*2(%edi)
	movl	%edx, 8*3(%edi)
	movl	%edx, 8*4(%edi)
	movl	%edx, 8*5(%edi)
	movl	%edx, 8*6(%edi)
	movl	%edx, 8*7(%edi)
	movl	%edx, 8*8(%edi)
	movl	%edx, 8*9(%edi)
	movl	%edx, 8*10(%edi)
	movl	%edx, 8*11(%edi)
	movl	%edx, 8*12(%edi)
	movl	%edx, 8*13(%edi)
	movl	%edx, 8*14(%edi)
	movl	%edx, 8*15(%edi)

	// Enable and activate Long Mode.  From the manual:
	// Make sure Page Size Extentions are off, and Page Global
	// Extensions and Physical Address Extensions are on in CR4;
	// set Long Mode Enable in the Extended Feature Enable MSR;
	// set Paging Enable in CR0;
	// make an inter-segment jump to the Long Mode code.
	// It`s all in 32-bit mode until the jump is made.
	movl	%cr4, %eax
	andl	$~Cr4PSE, %eax		// PSE always true in PAE mode
	orl	$(Cr4PGE|Cr4PAE), %eax	// Page Global, Phys. Address
	movl	%eax, %cr4

	movl	$IA32_EFER, %ecx	// Extended Feature Enable
	rdmsr
	// Enable long mode, NX bit in PTEs and SYSCALL/SYSREG.
	orl	$(EferSCE|EferLME|EferNXE), %eax
	wrmsr

	movl	%cr0, %eax
	andl	$~(Cr0CD|Cr0NW|Cr0TS|Cr0MP), %eax
	orl	$(Cr0PG|Cr0WP), %eax		// Paging Enable
	movl	%eax, %cr0

	// Load the 64-bit GDT
	movl	$(gdtdesc-KZERO), %eax
	lgdt	(%eax)

	ljmpl	$GdtCODE64, $(1f-KZERO)

.code64
1:
	// Long mode. Welcome to 2003.  Jump out of the identity map
	// and into the kernel address space.

	// Load a 64-bit GDT in the kernel address space.
	movabsq	$gdtdescv, %rax
	lgdt	(%rax)

	// Zero out the segment registers: they are not used in long mode.
	xorl	%eax, %eax
	movw	%ax, %ds
	movw	%ax, %es
	movw	%ax, %ss
	movw	%ax, %fs
	movw	%ax, %gs

	// We can now use linked addresses for the stack and code.
	// We'll jump into the kernel from here.
	movabsq	$(KZERO+KMACH), %rdi
	leaq	MACHSTKOFF+MACHSTKSZ(%rdi), %rsp
	movabsq	$warp64, %rax
	pushq	%rax
	ret

warp64:
	// At this point, we are fully in the kernel virtual
	// address space and can discard the identity mapping.
	// Perhaps ironically, we use the existing identity
	// mapping to do so, but as we're merely clearing an
	// an entry
	leaq	PGSZ(%ebx), %rax
	movq	$0, (%rax)
	movq	%rax, %cr3			// Also flushes TLB.

	// A pointer to the Mach is the first argument to `main`
	movq	%rbp, %rsi			// multiboot info pointer

	// Push a dummy stack frame and jump to `main`.
	pushq	$0
	movq	$0, %rbp
	leaq	main(%rip), %rax
	push	%rax
	pushq	$2				// clear flags
	popfq
	ret
	ud2

// no deposit, no return
// do not resuscitate
.text
.code64
.globl ndnr
ndnr:
	cli
	hlt
	jmp	ndnr

// Start-up request IPI handler.
//
// This code is executed on an application processor in response
// to receiving a Start-up IPI (SIPI) from another processor.  The
// vector given in the SIPI determines the memory address the
// where the AP starts execution.
//
// The AP starts in 16-bit real-mode, with:
//  - CS selector set to the startup memory address/16;
//  - CS base set to startup memory address;
//  - CS limit set to 64KiB;
//  - CPL and IP set to 0;
//  - A20 latch disabled.
// Welcome to 1978.
//
// This must be placed on a 4KiB boundary, and while it may seem
// like this should be in a text section, it is deliberately not.
// The AP entry code is copied to a page in low memory at APENTRY
// for execution, so as far as the rest of the kernel is concerned,
// the assembled and linked instructions here are just read-only
// data.  We put it into .rodata so that it is mapped onto a
// non-executable page and the kernel cannot accidentally jump
// into it once it is running in Rust code on a real page table.
//
// Note that the physical address of the `Mach` for this AP is
// copied into the last 8 bytes of the AP startup page.  We can
// use this to establish an early mapping for the kernel, until
//
// The 16-bit code loads a basic GDT, turns on 32-bit protected
// mode and makes an inter-segment jump to the protected mode code
// right after.
//
// 32-bit code enables long mode and paging, sets a stack and
// jumps to 64-bit mode, which fixes up virtual addresses for
// the stack and PC and jumps into C.

.set APENTRY,		0x7000
.set APMACHPML3,	(APENTRY+PGSZ-8)

.section .rodata

.globl b1978, e1978
.balign 16
.code16
b1978:
	// We start here in real mode.  Welcome to 1978.
	cli
	cld

	lgdtl	(APENTRY+(apgdtdesc-b1978))

	movl	%cr0, %eax
	orl	$Cr0PE, %eax
	movl	%eax, %cr0

	ljmpl   $GdtCODE32, $(b1982-KZERO)

.balign 16
gdt:
	// 0: Null segment
	.quad	0
	// 8: Kernel 64-bit code segment
	.quad	(SegREAD|SegCODE|SegMB1|SegPRESENT|SegLONG)
	// 16: Kernel 32-bit code segment (for bootstrapping APs)
	.quad	(SegREAD|SegCODE|SegMB1|SegPRESENT|Seg32DEF)
	// 24: Kernel 32-bit data segment (for bootstrapping APs)
	.quad	(SegREAD|SegWRITE|SegMB1|SegPRESENT|Seg32DEF)
egdt:

.balign 16
.skip 6
gdtdesc:
	.word	egdt - gdt - 1
	.long	(gdt - KZERO)

.balign 16
.skip 6
gdtdescv:
	.word	egdt - gdt - 1
	.quad	gdt

.skip 6
apgdtdesc:
.word	egdt - gdt - 1
.long	(APENTRY+gdt-b1978)

e1978:

.code32
b1982:
	// Protected mode. Welcome to 1982.
	movw	$GdtDATA32, %ax
	movw	%ax, %ds
	movw	%ax, %es
	movw	%ax, %ss

	xorl	%eax, %eax
	movw	%ax, %fs
	movw	%ax, %gs

	// In order to fully boot, we need our Mach, as it contains
	// the PML4 we need to use for this AP.  However, this is
	// actually somewhat of a problem: the Mach could be anywhere
	// in the physical address space, not necessarily in the low
	// 4 GiB, and so we won't necessarily be able to access it
	// until we have paging enabled.  Moreover, even if we were
	// passed the physical address of the Mach, the pages that
	// make it up may not be physically contiguous.
	//
	// We could pass the physical address of the PML4 from the Mach,
	// but again, it could be anywhere in the physical address space,
	// not necessarily in the low 4GiB, so we may not be able to
	// load it into %cr3 until after we've entered long mode, which
	// requires turning on paging.  Also, we still need an early
	// boot identity map; given that code running in a fully-formed
	// address space has already set up the address space for the
	// AP, we would prefer not to do that on aesthetic grounds.
	//
	// However, there is a solution.  We can pass the physical
	// address of the PML3 that covers the kernel from the Mach,
	// and borrow an unused page at the 1MiB mark to create a
	// temporary, self-referential PML4, and use it double-map
	// the kernel's address space so that we can get into long
	// mode.  Once there, we can use the self-referential map to
	// look up the Mach (which is at a fixed address on each CPU)
	// and find the physical address of its PML4, which we load
	// into %cr3, thus discarding the identity mapping.
	movl	$KSYS, %edi
	movl	%edi, %edx
	orl	$(PteRW|PteP), %edx
	movl	%edx, PGSZ-8(%edi)
	movl	APMACHPML3, %edx
	orl	$(PteRW|PteP), %edx
	movl	%edx, (%edi)
	movl	%edx, PGSZ/2(%edi)
	movl	APMACHPML3+4, %edx
	movl	%edx, 4(%edi)
	movl	%edx, PGSZ/2+4(%edi)
	movl	%edi, %cr3

	// Enable and activate Long Mode.
	movl	%cr4, %eax
	andl	$~Cr4PSE, %eax		// PSE always true in long mode
	orl	$(Cr4PGE|Cr4PAE), %eax	// Page Global, Phys. Address Ext
	movl	%eax, %cr4

	movl	$IA32_EFER, %ecx	// Extended Feature Enable
	rdmsr
	orl	$(EferSCE|EferLME|EferNXE), %eax
	wrmsr				// Long Mode Enable

	movl	%cr0, %edx
	andl	$~(Cr0CD|Cr0NW|Cr0TS|Cr0MP), %edx
	orl	$(Cr0PG|Cr0WP), %edx	// Paging Enable
	movl	%edx, %cr0

	ljmp	$GdtCODE64, $(1f-KZERO)

.code64
1:
	movabsq	$(KZERO+KMACH), %rdi
	leaq	MACHSTKOFF+MACHSTKSZ(%rdi), %rsp
	movabsq	$apwarp64, %rax
	pushq	%rax
	ret
	ud2

apwarp64:
	movabsq	$gdtdescv, %rax
	lgdt	(%rax)

	xorl	%eax, %eax
	movw	%ax, %ds
	movw	%ax, %es
	movw	%ax, %fs
	movw	%ax, %gs
	movw	%ax, %ss

	// Move to the real PML4.
	leaq	PGSZ(%rdi), %rax
	sarq	$12, %rax
	movq	(%rax), %rax
	movq	%rax, %cr3

	pushq	$0
	movq	$0, %rbp
	movq	8(%rdi), %rax			// m->splpc
	pushq	%rax
	pushq	$2				// Clear flags
	popfq
	ret					// Call squidboy
	ud2
