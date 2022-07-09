// Aarch64 entry (Raspberry Pi 3, 4 focussed)
 
.section .boottext, "awx"
.globl start

start:
	// All cores other than 0 should just hang
    mrs     x1, mpidr_el1
    and     x1, x1, #3
    cbnz    x1, 5f
	
	// On the main core, so set up the initial stack
	ldr		x5, =start
	add		x5, x5, #4096
	mov		sp, x5

	// Clean the BSS section
    ldr     x1, =bss     		// Start address
    ldr     w2, =end  		    // End of bss
3:  cbz     w2, 4f              // Quit loop if zero
    str     xzr, [x1], #8
    sub     w2, w2, #1
    cbnz    w2, 3b              // Loop if non-zero

4:	bl main9

5:
	wfe
	b		5b