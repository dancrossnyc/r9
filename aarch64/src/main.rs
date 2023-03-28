#![feature(alloc_error_handler)]
#![feature(asm_const)]
#![feature(stdsimd)]
#![cfg_attr(not(any(test, feature = "cargo-clippy")), no_std)]
#![cfg_attr(not(test), no_main)]
#![allow(clippy::upper_case_acronyms)]
#![forbid(unsafe_op_in_unsafe_fn)]

mod devcons;
mod io;
mod mailbox;
mod registers;
mod trap;
mod uartmini;
mod uartpl011;

use core::ffi::c_void;
use port::fdt::DeviceTree;
use port::println;

#[cfg(not(test))]
core::arch::global_asm!(include_str!("l.S"));

unsafe fn print_memory_range(name: &str, start: &*const c_void, end: &*const c_void) {
    let start = start as *const _ as u64;
    let end = end as *const _ as u64;
    let size = end - start;
    println!("  {name}{start:#x}-{end:#x} ({size:#x})");
}

fn print_binary_sections() {
    extern "C" {
        static boottext: *const c_void;
        static eboottext: *const c_void;
        static text: *const c_void;
        static etext: *const c_void;
        static rodata: *const c_void;
        static erodata: *const c_void;
        static data: *const c_void;
        static edata: *const c_void;
        static bss: *const c_void;
        static end: *const c_void;
    }

    println!("Binary sections:");
    unsafe {
        print_memory_range("boottext:\t", &boottext, &eboottext);
        print_memory_range("text:\t\t", &text, &etext);
        print_memory_range("rodata:\t", &rodata, &erodata);
        print_memory_range("data:\t\t", &data, &edata);
        print_memory_range("bss:\t\t", &bss, &end);
        print_memory_range("total:\t", &boottext, &end);
    }
}

fn print_physical_memory_map() {
    let mailbox::ArmMemory { start, size, end } = mailbox::get_arm_memory();

    println!("Physical memory map:");
    println!("  Memory:\t{start:#018x}-{end:#018x} ({size:#x})");
}

#[no_mangle]
pub extern "C" fn main9(dtb_ptr: u64) {
    trap::init();

    let dt = unsafe { DeviceTree::from_u64(dtb_ptr).unwrap() };
    mailbox::init(&dt);
    devcons::init(&dt);

    println!();
    println!("r9 from the Internet");
    println!("DTB found at: {:#x}", dtb_ptr);
    print_binary_sections();

    // Assume we've got MMU set up, so drop early console for the locking console
    port::devcons::drop_early_console();

    print_physical_memory_map();

    println!("looping now");

    #[allow(clippy::empty_loop)]
    loop {}
}

mod runtime;
