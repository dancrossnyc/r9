use crate::registers::EsrEl1;
use core::fmt;
use port::println;

#[cfg(not(test))]
core::arch::global_asm!(include_str!("interrupts.S"));

pub fn init() {
    unsafe { init_interrupts() };
}

extern "C" {
    fn init_interrupts();
}

/// Register frame at time interrupt was taken
#[derive(Copy, Clone)]
#[repr(C)]
pub struct InterruptFrame {
    x0: u64,
    x1: u64,
    x2: u64,
    x3: u64,
    x4: u64,
    x5: u64,
    x6: u64,
    x7: u64,
    x8: u64,
    x9: u64,
    x10: u64,
    x11: u64,
    x12: u64,
    x13: u64,
    x14: u64,
    x15: u64,
    x16: u64,
    x17: u64,
    x18: u64,
    frame_pointer: u64, // x29
    link_register: u64, // x30
    esr_el1: EsrEl1,
    elr_el1: u64,
    far_el1: u64,
    interrupt_type: u64,
    xzr: u64, // zero padding
}

impl fmt::Debug for InterruptFrame {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("InterruptFrame")
            .field("x0", &format_args!("{:#018x}", self.x0))
            .field("x1", &format_args!("{:#018x}", self.x1))
            .field("x2", &format_args!("{:#018x}", self.x2))
            .field("x3", &format_args!("{:#018x}", self.x3))
            .field("x4", &format_args!("{:#018x}", self.x4))
            .field("x5", &format_args!("{:#018x}", self.x5))
            .field("x6", &format_args!("{:#018x}", self.x6))
            .field("x7", &format_args!("{:#018x}", self.x7))
            .field("x8", &format_args!("{:#018x}", self.x8))
            .field("x9", &format_args!("{:#018x}", self.x9))
            .field("x10", &format_args!("{:#018x}", self.x10))
            .field("x11", &format_args!("{:#018x}", self.x11))
            .field("x12", &format_args!("{:#018x}", self.x12))
            .field("x13", &format_args!("{:#018x}", self.x13))
            .field("x14", &format_args!("{:#018x}", self.x14))
            .field("x15", &format_args!("{:#018x}", self.x15))
            .field("x16", &format_args!("{:#018x}", self.x16))
            .field("x17", &format_args!("{:#018x}", self.x17))
            .field("x18", &format_args!("{:#018x}", self.x18))
            .field("frame_pointer", &format_args!("{:#018x}", self.frame_pointer))
            .field("link_register", &format_args!("{:#018x}", self.link_register))
            .field("esr_el1", &format_args!("{:?}", self.esr_el1))
            .field("elr_el1", &format_args!("{:#018x}", self.elr_el1))
            .field("far_el1", &format_args!("{:#018x}", self.far_el1))
            .field("interrupt_type", &format_args!("{:#018x}", self.interrupt_type))
            .field("xzr", &format_args!("{:#018x}", self.xzr))
            .finish()
    }
}

#[no_mangle]
pub extern "C" fn handle_exception_with_ptr(frame: *mut InterruptFrame) {
    unsafe { handle_exception(&mut *frame) }
}

fn handle_exception(frame: &mut InterruptFrame) {
    // Just print out the frame and loop for now
    println!("{:?}", frame);
    loop {}
}
