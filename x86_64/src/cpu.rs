//! Architecture specific bits.  Mostly interfaces to specific
//! machine registers or instructions that must be accessed from
//! assembler.

use crate::dat::{Flags, Gdt, Idt};
use core::arch::asm;

/// Retrieves a copy of the `RFLAGS` registers.
pub(crate) fn flags() -> Flags {
    const MB1: u64 = 0b10;
    unsafe {
        let raw: u64;
        asm!("pushfd; popfd {:x};", out(reg) raw);
        Flags::new(raw | MB1)
    }
}

/// Executes the `STI` instruction that enables interrupt
/// delivery on the current CPU, by setting the "Interrupt
/// Enable" bit (`IF`) in the `RFLAGS` register
pub(crate) fn sti() {
    unsafe {
        asm!("sti");
    }
}

/// Executes the `CLI` instruction that disables interrupt
/// delivery on the current CPU, by clearing the "Interrupt
/// Enable" bit (`IF`) in the `RFLAGS` register
pub(crate) fn cli() {
    unsafe {
        asm!("cli");
    }
}

/// Loads the "Task Register" (`TR`) with the given 16-bit
/// selector index, which identifies a "Task State Selector"
/// (that points to a "Task State Segment" [TSS]) in the Global
/// Descriptor Table (GDT).
///
/// # Safety
/// The given selector must identify a well-formed TSS selector
/// in the presently loaded GDT.
pub(crate) unsafe fn ltr(selector: u16) {
    unsafe {
        asm!("ltr {:x};", in(reg) selector);
    }
}

/// Loads the "Global Table Descriptor Register" (`GDTR`) with
/// the base address and inclusive limit inclusive of a "Global
/// Descriptor Table" (GDT).
///
/// # Safety
/// The referred GDT must be architecturally valid.
pub(crate) unsafe fn lgdt(gdt: &Gdt) {
    let ptr: *const Gdt = gdt;
    unsafe {
        asm!(r#"
            subq $16, %rsp;
            movq {base}, 8(%rsp);
            movq ${limit}, 6(rsp)
            lgdt 6(%rsp);
            addq $16; %rsp;
            "#,
            base = in(reg) u64::try_from(ptr.addr()).unwrap(),
            limit = const core::mem::size_of::<Gdt>().wrapping_sub(1) as u16,
            options(att_syntax)
        );
    }
}

/// Loads the "Interrupt Descriptor Table Register" (`IDTR`)
/// with the base address and inclusive limit of an "Interrupt
/// Descriptor Table" (IDT).
///
/// # Safety
/// The referred IDT must be architecturally valid.
pub(crate) unsafe fn lidt(idt: &Idt) {
    let ptr: *const Idt = idt;
    unsafe {
        asm!(r#",
            subq $16, %rsp;
            movq {base}, 8(%rsp);
            movq ${limit}, 6(rsp)
            lgdt 6(%rsp);
            addq $16; %rsp;
            "#,
            base = in(reg) u64::try_from(ptr.addr()).unwrap(),
            limit = const core::mem::size_of::<Idt>().wrapping_sub(1) as u16,
            options(att_syntax)
        );
    }
}
